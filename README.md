# terraform-kubernetes-cilium

Installs [Cilium](https://cilium.io) as the CNI on an existing Kubernetes cluster, with Terraform owning its lifecycle: the CNI sits outside the cluster it serves, so it stays recoverable when the cluster's own GitOps controller is down. Run it after the cluster is up (nodes stay NotReady until Cilium is in) and before the GitOps controller.

Written for k3s on bare VPS (`flannel-backend: none`, `disable-kube-proxy: true`), works on any cluster with a reachable apiserver.

What it sets up:

- kube-proxy replacement and a full eBPF datapath (`bpf.masquerade`);
- WireGuard encryption of pod traffic;
- Gateway API: applies the pinned standard-channel CRDs, then enables the controller in host-network mode, so Envoy binds :80/:443 on the node directly (no LoadBalancer needed);
- optional Host Firewall, so host-scoped `CiliumClusterwideNetworkPolicy` can close node ports like :6443 and :10250;
- Bandwidth Manager with BBR, Local Redirect Policy, Hubble with UI, Prometheus metrics;
- drop events off: on hosters that run VRRP on the node's L2 segment they flood Hubble's parser and grow the agent heap to around 1 GiB.

`gateway_api_version` is coupled to `cilium_version`. If the CRDs are older than the operator expects, it disables its Gateway API controller while staying Ready, and every HTTPS listener resets the handshake. Bump both together.

## Usage

```hcl
module "cilium" {
  source = "git::https://github.com/sanchpet/terraform-kubernetes-cilium.git?ref=v0.1.0"

  kubeconfig_context   = "my-cluster"
  cilium_version       = "1.20.1"
  gateway_api_version  = "v1.5.1"
  enable_host_firewall = true
}
```

A k3s agent has no local apiserver on :6443; on clusters with agents set `k8s_service_port = 6444`, which both servers and agents expose.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.17 |
| <a name="requirement_http"></a> [http](#requirement\_http) | ~> 3.4 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 2.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 2.17 |
| <a name="provider_http"></a> [http](#provider\_http) | ~> 3.4 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | ~> 2.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubectl_manifest.gateway_api_crds](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [http_http.gateway_api_crds](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |
| [kubectl_file_documents.gateway_api_crds](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/data-sources/file_documents) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cilium_version"></a> [cilium\_version](#input\_cilium\_version) | Cilium Helm chart version (pinned; bump deliberately — it is a critical dataplane). | `string` | n/a | yes |
| <a name="input_kubeconfig_context"></a> [kubeconfig\_context](#input\_kubeconfig\_context) | kubeconfig context of the target cluster (the k3s collection sets one per cluster). | `string` | n/a | yes |
| <a name="input_config_hash_annotation"></a> [config\_hash\_annotation](#input\_config\_hash\_annotation) | Pod annotation key that carries the hash of the Cilium values, so any values change rolls the agent and operator. Changing the key itself rolls them once; a consumer migrating from an earlier copy of this module keeps its old key to avoid that. | `string` | `"terraform-kubernetes-cilium/config-hash"` | no |
| <a name="input_enable_bandwidth_manager"></a> [enable\_bandwidth\_manager](#input\_enable\_bandwidth\_manager) | EDT-based egress bandwidth shaping + BBR congestion control for pods (throughput/latency for an internet-facing hub; needs a recent kernel). | `bool` | `true` | no |
| <a name="input_enable_bpf_masquerade"></a> [enable\_bpf\_masquerade](#input\_enable\_bpf\_masquerade) | Masquerade pod egress in eBPF instead of iptables — completes the kube-proxy-free datapath. | `bool` | `true` | no |
| <a name="input_enable_gateway_api"></a> [enable\_gateway\_api](#input\_enable\_gateway\_api) | Enable Cilium Gateway API (installs the standard Gateway API CRDs first, then the controller). | `bool` | `true` | no |
| <a name="input_enable_gateway_hostnetwork"></a> [enable\_gateway\_hostnetwork](#input\_enable\_gateway\_hostnetwork) | Run the Gateway API in host-network mode — the gateway's Envoy binds host ports directly (no LoadBalancer Service / no k3s ServiceLB). The reachability path for bare VPS with no announceable VIP; DNS-RR over the public node IPs. Also grants Envoy NET\_BIND\_SERVICE for :80/:443. | `bool` | `true` | no |
| <a name="input_enable_host_firewall"></a> [enable\_host\_firewall](#input\_enable\_host\_firewall) | Enable the Cilium Host Firewall (enforce host-scoped CiliumClusterwideNetworkPolicy on the node's network namespace). Capability only — the host stays default-allow until a host-selecting policy exists. The eBPF-native way to firewall :6443/:10250 under kube-proxy-free, where nftables/netfilter conflicts. | `bool` | `false` | no |
| <a name="input_enable_host_port"></a> [enable\_host\_port](#input\_enable\_host\_port) | Enable Cilium hostPort mapping (eBPF). Under kube-proxy-free, Cilium — not the portmap CNI — publishes a pod's hostPort. Needed only where a workload binds a host port directly; the host-network Gateway API does not use hostPort, so this stays off by default. | `bool` | `false` | no |
| <a name="input_enable_hubble"></a> [enable\_hubble](#input\_enable\_hubble) | Enable Hubble (flow observability) + relay. | `bool` | `true` | no |
| <a name="input_enable_hubble_ui"></a> [enable\_hubble\_ui](#input\_enable\_hubble\_ui) | Enable the Hubble UI (adds pods). | `bool` | `true` | no |
| <a name="input_enable_local_redirect_policy"></a> [enable\_local\_redirect\_policy](#input\_enable\_local\_redirect\_policy) | Enable Local Redirect Policy (redirect to node-local backends, e.g. a node-local DNS cache). | `bool` | `true` | no |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | Expose Cilium agent + operator (+ Hubble) Prometheus metrics endpoints. | `bool` | `true` | no |
| <a name="input_enable_wireguard"></a> [enable\_wireguard](#input\_enable\_wireguard) | Transparent WireGuard encryption of pod traffic (closes flannel's cleartext gap). | `bool` | `true` | no |
| <a name="input_extra_values"></a> [extra\_values](#input\_extra\_values) | Extra Cilium Helm values as a raw YAML string, deep-merged last (escape hatch). | `string` | `""` | no |
| <a name="input_gateway_api_version"></a> [gateway\_api\_version](#input\_gateway\_api\_version) | Gateway API release whose standard CRDs are installed (must satisfy the floor the pinned Cilium validates at operator start). | `string` | `"v1.5.1"` | no |
| <a name="input_k8s_service_host"></a> [k8s\_service\_host](#input\_k8s\_service\_host) | API server host for kube-proxy replacement. 127.0.0.1 when every node runs a local apiserver (k3s HA servers). | `string` | `"127.0.0.1"` | no |
| <a name="input_k8s_service_port"></a> [k8s\_service\_port](#input\_k8s\_service\_port) | API server port for kube-proxy replacement. Default 6443 is a k3s server's local apiserver; a cluster with k3s AGENT nodes must use 6444 (the supervisor load-balancer that agents reach the API through — a server exposes both, so 6444 works cluster-wide). | `number` | `6443` | no |
| <a name="input_kubeconfig_path"></a> [kubeconfig\_path](#input\_kubeconfig\_path) | Path to the kubeconfig for the target cluster (~ is expanded). | `string` | `"~/.kube/config"` | no |
| <a name="input_operator_replicas"></a> [operator\_replicas](#input\_operator\_replicas) | Cilium operator replica count (1 for small clusters). | `number` | `1` | no |
| <a name="input_pod_cidr_list"></a> [pod\_cidr\_list](#input\_pod\_cidr\_list) | Cilium cluster-pool IPv4 pod CIDRs. MUST NOT overlap the node/service CIDRs (k3s default pod CIDR is 10.42.0.0/16; Cilium's own default 10.0.0.0/8 would clash with a 10.0.0.0/8 node net). | `list(string)` | <pre>[<br/>  "10.42.0.0/16"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cilium_version"></a> [cilium\_version](#output\_cilium\_version) | Installed Cilium chart version. |
| <a name="output_gateway_api_enabled"></a> [gateway\_api\_enabled](#output\_gateway\_api\_enabled) | Whether the Cilium Gateway API controller is enabled. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace Cilium is installed into. |
<!-- END_TF_DOCS -->
