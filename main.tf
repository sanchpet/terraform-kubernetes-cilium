# Cilium CNI, owned by Terraform: the CNI's lifecycle sits outside the cluster it manages, so it
# stays recoverable when the cluster's own GitOps is down. Runs after k3s is up (Ansible) and
# before a GitOps controller is installed.

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kubeconfig_context
  }
}

provider "kubectl" {
  config_path      = pathexpand(var.kubeconfig_path)
  config_context   = var.kubeconfig_context
  load_config_file = true
}

# --- Gateway API CRDs -----------------------------------------------------------------------
# Cilium's Gateway API controller requires the standard-channel CRDs pre-installed. Fetch the
# pinned upstream bundle and server-side-apply it (CRDs are large — SSA avoids the last-applied
# annotation size limit). Fetched unconditionally (a cheap GET) to keep the for_each type simple;
# nothing is applied when enable_gateway_api is false.
#
# gateway_api_version is COUPLED to cilium_version, and the coupling fails quietly: the operator
# validates these CRDs once at start and, finding them too old, disables its entire Gateway API
# controller while staying Running and Ready. Nothing programs the listeners and nothing syncs
# gateway TLS into cilium-secrets, so every HTTPS host accepts TCP and resets the handshake —
# a total outage of the public surface that looks like a network fault from outside. Bump both
# together and check the operator log for "Required GatewayAPI resources are not found".
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = var.enable_gateway_api ? data.kubectl_file_documents.gateway_api_crds.manifests : {}

  yaml_body         = each.value
  server_side_apply = true
}

# --- Cilium ---------------------------------------------------------------------------------
locals {
  # Base Cilium helm values. The config-hash (below) is derived from these and merged back in as
  # podAnnotations — put NEW config HERE, in the base, not in the merged `cilium_values`.
  cilium_values_base = {
    kubeProxyReplacement = true
    k8sServiceHost       = var.k8s_service_host
    k8sServicePort       = var.k8s_service_port

    # cluster-pool IPAM with an explicit pod CIDR — Cilium's default 10.0.0.0/8 would overlap a
    # 10.x provider network. Keep pods on the k3s-default 10.42.0.0/16.
    ipam = {
      mode = "cluster-pool"
      operator = {
        clusterPoolIPv4PodCIDRList = var.pod_cidr_list
      }
    }

    # Full eBPF datapath: masquerade pod egress in eBPF (no iptables SNAT), completing the
    # kube-proxy-free setup.
    bpf = {
      masquerade = var.enable_bpf_masquerade

      # Drop events OFF, and this is a memory decision rather than an observability one. SpaceWeb
      # runs its gateway redundancy on the node's L2 segment, so the node receives VRRPv2
      # advertisements every second that Cilium counts as drops; with drop events on, Hubble parses
      # each one and the agent's heap grows to around 1 GiB (measured on other SpaceWeb nodes, about
      # ten times the same image on another hoster). Policy decisions stay visible through
      # bpf.events.policyVerdict, which remains on.
      events = {
        drop = {
          enabled = false
        }
      }
    }

    # Node-local backends (e.g. a node-local DNS cache) via Local Redirect Policy.
    localRedirectPolicy = var.enable_local_redirect_policy

    # Host Firewall: enforce host-scoped CiliumClusterwideNetworkPolicy on the node's own network
    # namespace — the eBPF-native way to firewall node ports (:6443/:10250) off the public
    # internet, since nftables/netfilter conflicts with kube-proxy-free.
    # Capability only: the host stays default-allow until a host-selecting CCNP exists; `devices`
    # is auto-detected. Lockout-sensitive — a host CCNP enforces the moment it exists (audit mode
    # is imperative and does not survive an agent restart), so roll one out deliberately.
    hostFirewall = {
      enabled = var.enable_host_firewall
    }

    # hostPort mapping via eBPF — Cilium (not the portmap CNI) publishes a pod's hostPort under
    # kube-proxy-free. Needed only where a workload binds a host port directly; the host-network
    # Gateway does not use hostPort, so it stays off unless a cluster opts in.
    hostPort = {
      enabled = var.enable_host_port
    }

    # EDT-based egress shaping + BBR congestion control for pods — better throughput/latency on the
    # internet paths. Needs a recent kernel (Debian 13 = 6.x).
    bandwidthManager = {
      enabled = var.enable_bandwidth_manager
      bbr     = var.enable_bandwidth_manager
    }

    # Agent metrics for Prometheus.
    prometheus = {
      enabled = var.enable_prometheus
    }

    # cilium-agent (DaemonSet) requests. No memory LIMIT on purpose: an OOM-killed agent takes the
    # node's networking down — request-only lets the scheduler plan without a fatal cap.
    resources = {
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
    }

    operator = {
      replicas   = var.operator_replicas
      prometheus = { enabled = var.enable_prometheus }
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
      }
    }

    encryption = {
      enabled = var.enable_wireguard
      type    = "wireguard" # ignored when disabled
    }

    hubble = {
      enabled = var.enable_hubble
      relay = {
        enabled   = var.enable_hubble
        resources = { requests = { cpu = "50m", memory = "64Mi" } }
      }
      ui = {
        enabled  = var.enable_hubble_ui
        frontend = { resources = { requests = { cpu = "25m", memory = "64Mi" } } }
        backend  = { resources = { requests = { cpu = "25m", memory = "64Mi" } } }
      }
      # L3–L7 flow metrics (empty list = disabled). `drop` is absent because bpf.events.drop is off
      # and nothing would feed it; `port-distribution` is absent because it labels one series per
      # destination port, which is unbounded on any node that carries egress traffic.
      metrics = {
        enabled = var.enable_prometheus && var.enable_hubble ? ["dns", "tcp", "flow", "icmp", "httpV2"] : []
      }
    }

    gatewayAPI = {
      enabled = var.enable_gateway_api
      # Host-network mode: the gateway's Envoy binds its listener ports directly on each node's
      # host — no LoadBalancer Service, no k3s ServiceLB/klipper: a bare VPS has no announceable
      # VIP, so DNS points at the node's public IP.
      hostNetwork = {
        enabled = var.enable_gateway_hostnetwork
      }
    }

    # Cilium's standalone Envoy DaemonSet needs NET_BIND_SERVICE to bind the privileged :80/:443
    # host ports for the host-network Gateway API. capabilities.envoy REPLACES the default set,
    # so it must also carry the datapath caps — verified from the live pod, the default is
    # NET_ADMIN + SYS_ADMIN (dropping either CrashLoops: "CAP_NET_ADMIN and either CAP_SYS_ADMIN
    # or CAP_BPF ... needed"). keepCapNetBindService alone does not add the cap — Envoy then fails
    # with "cannot bind 0.0.0.0:80: Permission denied". keepCapNetBindService retains it after bind.
    envoy = {
      securityContext = {
        capabilities = {
          keepCapNetBindService = true
          envoy                 = ["NET_ADMIN", "SYS_ADMIN", "NET_BIND_SERVICE"]
        }
      }
    }
  }

  # Roll cilium-agent + cilium-operator whenever ANY value changes. Helm only rolls pods on a
  # pod-template change, so config-only edits (the cilium-config ConfigMap — e.g. gateway
  # hostNetwork) otherwise leave the running pods on stale in-memory config until a MANUAL
  # `kubectl rollout restart`. Stamping the values hash into podAnnotations moves the pod
  # template on every config change, so helm restarts the pods and they re-read the config.
  # Kept inside Cilium's Terraform-owned lifecycle — not delegated to a GitOps-layer reloader,
  # which would invert the layering (a platform app restarting the foundation).
  cilium_config_hash = sha256(jsonencode(local.cilium_values_base))

  cilium_values = merge(local.cilium_values_base, {
    podAnnotations = {
      (var.config_hash_annotation) = local.cilium_config_hash
    }
    operator = merge(local.cilium_values_base.operator, {
      podAnnotations = {
        (var.config_hash_annotation) = local.cilium_config_hash
      }
    })
  })
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  values = concat(
    [yamlencode(local.cilium_values)],
    var.extra_values == "" ? [] : [var.extra_values],
  )

  # The Gateway API CRDs must exist before Cilium starts its Gateway controller.
  depends_on = [kubectl_manifest.gateway_api_crds]

  # Installing onto a fresh, still-NotReady cluster: Cilium is what brings the nodes Ready, so
  # wait for the rollout (bounded) rather than racing ahead to the GitOps install.
  timeout = 600
  wait    = true
}
