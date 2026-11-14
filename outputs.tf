output "cilium_version" {
  description = "Installed Cilium chart version."
  value       = helm_release.cilium.version
}

output "namespace" {
  description = "Namespace Cilium is installed into."
  value       = helm_release.cilium.namespace
}

output "gateway_api_enabled" {
  description = "Whether the Cilium Gateway API controller is enabled."
  value       = var.enable_gateway_api
}
