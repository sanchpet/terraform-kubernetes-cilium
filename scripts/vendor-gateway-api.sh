#!/usr/bin/env bash
# Vendor a Gateway API release as a chart under charts/gateway-api-crds/<version>/.
#   scripts/vendor-gateway-api.sh [vX.Y.Z]   # vendor a version (default: the pinned one below)
#   scripts/vendor-gateway-api.sh --verify   # check every vendored bundle against upstream
set -euo pipefail

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
pinned="v1.5.1"

root="$(cd "$(dirname "$0")/.." && pwd)"
charts="$root/charts/gateway-api-crds"

asset_url() {
  echo "https://github.com/kubernetes-sigs/gateway-api/releases/download/$1/standard-install.yaml"
}

verify() {
  local dir version tmp failed=0
  [[ -f "$charts/$pinned/Chart.yaml" ]] || {
    echo "pinned $pinned is not vendored: run scripts/vendor-gateway-api.sh $pinned" >&2
    failed=1
  }
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  for dir in "$charts"/*/; do
    version="$(basename "$dir")"
    curl -fsSLo "$tmp" "$(asset_url "$version")"
    if [[ "$(sha256sum <"$tmp")" == "$(sha256sum <"$dir/files/standard-install.yaml")" ]]; then
      echo "$version: matches upstream"
    else
      echo "$version: files/standard-install.yaml differs from the upstream asset" >&2
      failed=1
    fi
  done
  return "$failed"
}

vendor() {
  local version="$1" dir="$charts/$1"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "expected vX.Y.Z, got $version" >&2
    exit 1
  }
  mkdir -p "$dir/files" "$dir/templates"
  curl -fsSLo "$dir/files/standard-install.yaml" "$(asset_url "$version")"
  cat >"$dir/Chart.yaml" <<YAML
apiVersion: v2
name: gateway-api-crds
description: Gateway API standard-channel CRDs, vendored verbatim from the upstream release.
type: application
version: ${version#v}
appVersion: $version
YAML
  # The bundle stays in files/ and is read through .Files.Get, so Go templating never parses
  # upstream text and the file stays byte-identical to the release asset.
  cat >"$dir/templates/crds.yaml" <<'TPL'
{{- range $doc := regexSplit "(?m)^---[ \t]*$" (.Files.Get "files/standard-install.yaml") -1 }}
{{- $obj := fromYaml $doc }}
{{- if hasKey $obj "Error" }}{{ fail $obj.Error }}{{ end }}
{{- if $obj.kind }}
{{- /* keep: uninstalling the release must not delete the CRDs and cascade-delete every route. */}}
{{- $_ := set $obj.metadata "annotations" (merge (dict "helm.sh/resource-policy" "keep") ($obj.metadata.annotations | default dict)) }}
---
{{ toYaml $obj }}
{{- end }}
{{- end }}
TPL
  echo "vendored $version into ${dir#"$root"/}"
}

case "${1:-}" in
  --verify) verify ;;
  "") vendor "$pinned" ;;
  *) vendor "$1" ;;
esac
