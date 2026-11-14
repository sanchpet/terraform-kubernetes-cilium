# Provider pinning for the k8s-cilium module (installs Cilium and the Gateway API CRDs via Helm).
#
# The module talks to an EXISTING cluster over its kubeconfig context (helm provider),
# so it runs after k3s is up (Ansible) and before the GitOps controller is installed.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    # take_ownership on helm_release arrived in 3.1.0.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    # Unused by any resource since v0.2.0, but the removed block for the v0.1.0 kubectl_manifest
    # instances needs the provider's schema, so it stays declared for as long as that block does.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}
