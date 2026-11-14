# Provider pinning for the k8s-cilium module (installs Cilium via Helm + the Gateway API CRDs).
#
# The module talks to an EXISTING cluster over its kubeconfig context (helm + kubectl providers),
# so it runs after k3s is up (Ansible) and before the GitOps controller is installed.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    # Gateway API CRDs are server-side-applied as raw manifests. alekc/kubectl is the maintained
    # fork of gavinbunney/kubectl.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
