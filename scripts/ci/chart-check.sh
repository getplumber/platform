#!/usr/bin/env bash
# Lint, unit-test and schema-validate the v2 chart. Runs in CI and locally.
# Needs: helm, the helm unittest plugin (v1.0.3), kubeconform (path via KUBECONFORM, default on PATH).
set -euo pipefail
cd "$(dirname "$0")/../.."
CHART=charts/plumber-platform
KUBECONFORM="${KUBECONFORM:-kubeconform}"
BASE="$CHART/tests/values/base.yaml"

helm lint "$CHART" -f "$BASE" --strict
helm unittest "$CHART"

validate() { # validate <label> [extra helm args...]
  local label="$1"; shift
  helm template plumber "$CHART" -f "$BASE" "$@" \
    | "$KUBECONFORM" -strict -summary -kubernetes-version 1.30.0 -schema-location default
  echo "  ok   kubeconform: $label"
}
validate "defaults"
validate "bundled db + redis + ingress tls" --set postgresql.deploy=true --set redis.deploy=true \
  --set ingress.enabled=true --set ingress.host=plumber.example.com --set ingress.tls.enabled=true
validate "existing secrets" --set platform.existingSecret=plumber-secrets --set platform.tokenEncryptionKey= \
  --set postgresql.global.postgresql.auth.existingSecret=pg-secret --set postgresql.global.postgresql.auth.password= \
  --set redis.auth.existingSecret=redis-secret --set redis.auth.password=
validate "custom ca + bootstrap job" --set customCertificateAuthority.certificates[0].name=ca.crt \
  --set customCertificateAuthority.certificates[0].value=dummy \
  --set bootstrap.enabled=true --set bootstrap.gitlabUrl=https://gitlab.example.com \
  --set bootstrap.clientId=abc --set bootstrap.existingSecret=bootstrap-secret
echo "chart-check: all good"
