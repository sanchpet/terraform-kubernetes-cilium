# terraform-kubernetes-cilium — instructions for Claude Code

Public Terraform module that installs Cilium on an existing cluster. Consumers pin it by git tag.

## Rules

- **Public repo.** No hostnames, IPs, accounts, node names, measurements tied to a specific fleet, or references to private repositories. The module describes *how* Cilium is configured; *which* cluster comes from the consumer.
- **Inputs are a contract.** Renaming or retyping a variable, or changing a default that alters the rendered Helm values, changes running clusters on their next apply (a values change rolls every agent). Treat it as a breaking change and say so in the PR.
- `gateway_api_version` and `cilium_version` move together.
- English for all repo artifacts, `--signoff` on every commit.
- **Conventional Commits + release-please.** PRs are squash-merged and the PR title is the release commit (CI checks it). Never tag or edit `CHANGELOG.md` by hand; merge the release PR. Release PRs opened by `GITHUB_TOKEN` get no CI run, so run the checks locally before merging one.
- Branch + PR.

## Checks

```sh
mise install
terraform fmt -check -recursive && terraform init -backend=false && terraform validate
tflint --init && tflint
terraform-docs .
```
