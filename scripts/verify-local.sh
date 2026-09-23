#!/usr/bin/env bash
# End-to-end check of the local platform. Every line either passes or explains
# what is missing, so a failure points at the component to look at.
set -uo pipefail

NS_ARGOCD="${1:-argocd}"
failed=0

check() { # description, command...
  local desc="$1"; shift
  if out=$("$@" 2>&1); then
    printf '  ok    %-42s %s\n' "$desc" "$out"
  else
    printf '  FAIL  %-42s %s\n' "$desc" "$out"
    failed=1
  fi
}

apps_ready() {
  kubectl get applications -n "$NS_ARGOCD" -o json | python3 -c '
import json, sys
bad = []
for app in json.load(sys.stdin)["items"]:
    status = app.get("status", {})
    if status.get("health", {}).get("status") != "Healthy":
        bad.append(app["metadata"]["name"])
if bad:
    print("unhealthy:", ", ".join(bad)); sys.exit(1)
print("all applications healthy")'
}

gateway_http() {
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:8080/)
  # 404 is the expected answer: the listener works, no route is attached yet.
  [ "$code" = "404" ] && echo "listener answers (HTTP $code)" || { echo "unexpected HTTP $code"; return 1; }
}

gateway_https() {
  # Any subdomain: the listener serves a wildcard certificate for *.platform.local,
  # which by design does not cover the bare domain.
  issuer=$(curl -sk --resolve unrouted.platform.local:8443:127.0.0.1 -v --max-time 10 \
    https://unrouted.platform.local:8443/ 2>&1 | sed -n 's/^\* *issuer: //p' | head -1)
  [ -n "$issuer" ] && echo "TLS terminated, issuer $issuer" || { echo "no TLS handshake"; return 1; }
}

secret_from_vault() {
  value=$(kubectl get secret -n demo demo-credentials -o jsonpath='{.data.message}' 2>/dev/null | base64 -d)
  [ -n "$value" ] && echo "\"$value\"" || { echo "secret not created by External Secrets"; return 1; }
}

grafana_through_gateway() {
  code=$(curl -sk --resolve grafana.platform.local:8443:127.0.0.1 -o /dev/null -w '%{http_code}' \
    --max-time 15 https://grafana.platform.local:8443/login)
  [ "$code" = "200" ] && echo "reachable over HTTPS (HTTP $code)" || { echo "unexpected HTTP $code"; return 1; }
}

echo "checking the local platform:"
check "Argo CD applications"          apps_ready
check "gateway, HTTP listener"        gateway_http
check "gateway, HTTPS listener"       gateway_https
check "secret synced from Vault"      secret_from_vault
check "Grafana behind the gateway"    grafana_through_gateway

exit $failed
