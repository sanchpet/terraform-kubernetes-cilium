variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the target cluster (~ is expanded)."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubeconfig context of the target cluster (the k3s collection sets one per cluster)."
  type        = string
}

variable "cilium_version" {
  description = "Cilium Helm chart version (pinned; bump deliberately — it is a critical dataplane)."
  type        = string
}

variable "k8s_service_host" {
  description = "API server host for kube-proxy replacement. 127.0.0.1 when every node runs a local apiserver (k3s HA servers)."
  type        = string
  default     = "127.0.0.1"
}

variable "k8s_service_port" {
  description = "API server port for kube-proxy replacement. Default 6443 is a k3s server's local apiserver; a cluster with k3s AGENT nodes must use 6444 (the supervisor load-balancer that agents reach the API through — a server exposes both, so 6444 works cluster-wide)."
  type        = number
  default     = 6443
}

variable "pod_cidr_list" {
  description = "Cilium cluster-pool IPv4 pod CIDRs. MUST NOT overlap the node/service CIDRs (k3s default pod CIDR is 10.42.0.0/16; Cilium's own default 10.0.0.0/8 would clash with a 10.0.0.0/8 node net)."
  type        = list(string)
  default     = ["10.42.0.0/16"]
}

variable "operator_replicas" {
  description = "Cilium operator replica count (1 for small clusters)."
  type        = number
  default     = 1
}

variable "enable_bpf_masquerade" {
  description = "Masquerade pod egress in eBPF instead of iptables — completes the kube-proxy-free datapath."
  type        = bool
  default     = true
}

variable "enable_local_redirect_policy" {
  description = "Enable Local Redirect Policy (redirect to node-local backends, e.g. a node-local DNS cache)."
  type        = bool
  default     = true
}

variable "enable_bandwidth_manager" {
  description = "EDT-based egress bandwidth shaping + BBR congestion control for pods (throughput/latency for an internet-facing hub; needs a recent kernel)."
  type        = bool
  default     = true
}

variable "enable_prometheus" {
  description = "Expose Cilium agent + operator (+ Hubble) Prometheus metrics endpoints."
  type        = bool
  default     = true
}

variable "enable_wireguard" {
  description = "Transparent WireGuard encryption of pod traffic (closes flannel's cleartext gap)."
  type        = bool
  default     = true
}

variable "enable_hubble" {
  description = "Enable Hubble (flow observability) + relay."
  type        = bool
  default     = true
}

variable "enable_hubble_ui" {
  description = "Enable the Hubble UI (adds pods)."
  type        = bool
  default     = true
}

variable "enable_host_firewall" {
  description = "Enable the Cilium Host Firewall (enforce host-scoped CiliumClusterwideNetworkPolicy on the node's network namespace). Capability only — the host stays default-allow until a host-selecting policy exists. The eBPF-native way to firewall :6443/:10250 under kube-proxy-free, where nftables/netfilter conflicts."
  type        = bool
  default     = false
}

variable "enable_host_port" {
  description = "Enable Cilium hostPort mapping (eBPF). Under kube-proxy-free, Cilium — not the portmap CNI — publishes a pod's hostPort. Needed only where a workload binds a host port directly; the host-network Gateway API does not use hostPort, so this stays off by default."
  type        = bool
  default     = false
}

variable "enable_gateway_api" {
  description = "Enable Cilium Gateway API (installs the standard Gateway API CRDs first, then the controller). Turning it off later leaves the CRDs in the cluster."
  type        = bool
  default     = true
}

variable "enable_gateway_hostnetwork" {
  description = "Run the Gateway API in host-network mode — the gateway's Envoy binds host ports directly (no LoadBalancer Service / no k3s ServiceLB). The reachability path for bare VPS with no announceable VIP; DNS-RR over the public node IPs. Also grants Envoy NET_BIND_SERVICE for :80/:443."
  type        = bool
  default     = true
}

variable "gateway_api_version" {
  description = "Gateway API release whose standard CRDs are installed (must satisfy the floor the pinned Cilium validates at operator start). One of the releases vendored under charts/gateway-api-crds/; plan fails on any other."
  type        = string
  default     = "v1.5.1"
}

variable "extra_values" {
  description = "Extra Cilium Helm values as a raw YAML string, deep-merged last (escape hatch)."
  type        = string
  default     = ""
}

variable "config_hash_annotation" {
  description = "Pod annotation key that carries the hash of the Cilium values, so any values change rolls the agent and operator. Changing the key itself rolls them once; a consumer migrating from an earlier copy of this module keeps its old key to avoid that."
  type        = string
  default     = "terraform-kubernetes-cilium/config-hash"
}
