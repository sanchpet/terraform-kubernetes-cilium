module "cilium" {
  source = "../.."

  kubeconfig_context   = "my-cluster"
  cilium_version       = "1.20.1"
  gateway_api_version  = "v1.5.1"
  enable_host_firewall = true
}
