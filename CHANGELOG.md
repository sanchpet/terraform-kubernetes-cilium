# Changelog

## [0.2.0](https://github.com/sanchpet/terraform-kubernetes-cilium/compare/v0.1.0...v0.2.0) (2026-11-14)


### ⚠ BREAKING CHANGES

* the helm provider moves to ~> 3.1 (take_ownership arrived in 3.1.0), so consumers run terraform init -upgrade once. gateway_api_version must now be a vendored release; plan fails on any other. No input changes.

### Features

* install Gateway API CRDs from a chart vendored in the module ([#3](https://github.com/sanchpet/terraform-kubernetes-cilium/issues/3)) ([0d878a0](https://github.com/sanchpet/terraform-kubernetes-cilium/commit/0d878a008ce3455518a5f08cff0e379f83cbd518))

## 0.1.0 (2026-11-14)


### Features

* Cilium module for k3s on bare VPS ([#1](https://github.com/sanchpet/terraform-kubernetes-cilium/issues/1)) ([d09059c](https://github.com/sanchpet/terraform-kubernetes-cilium/commit/d09059cf9726701f449dc60d1538510754911b1c))
