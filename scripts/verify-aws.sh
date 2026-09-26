#!/usr/bin/env bash
# End-to-end check of the platform running on EKS, the mirror of verify-local.sh.
# The point of this file existing twice is that the two are almost identical:
# what changes between environments is the plumbing, not the platform.
set -uo pipefail

# AWS only: the EKS cluster's own kubeconfig, written by `make up`.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/platform-eks-gitops-aws}"

NS_ARGOCD="${1:-argocd}"
failed=0

check() {
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
bad = [a["metadata"]["name"] for a in json.load(sys.stdin)["items"]
       if a.get("status", {}).get("health", {}).get("status") != "Healthy"]
if bad:
    print("unhealthy:", ", ".join(bad)); sys.exit(1)
print("all applications healthy")'
}

nodes_are_spot() {
  spot=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.eks\.amazonaws\.com/capacityType}{"\n"}{end}' | grep -c SPOT)
  total=$(kubectl get nodes --no-headers | wc -l)
  [ "$spot" = "$total" ] && echo "$spot of $total nodes on spot capacity" || { echo "only $spot of $total on spot"; return 1; }
}

store_valid() {
  reason=$(kubectl get clustersecretstore platform -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
  [ "$reason" = "Valid" ] && echo "Secrets Manager reachable with Pod Identity" || { echo "store is $reason"; return 1; }
}

secret_synced() {
  user=$(kubectl get secret -n monitoring grafana-admin -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d)
  [ -n "$user" ] && echo "credentials materialised for \"$user\"" || { echo "secret not created"; return 1; }
}

gateway_address() {
  host=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=platform \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$host" ] && echo "$host" || { echo "no load balancer yet"; return 1; }
}

grafana_through_gateway() {
  host=$(gateway_address) || return 1
  ip=$(getent hosts "$host" | awk '{print $1; exit}')
  [ -n "$ip" ] || { echo "load balancer name does not resolve yet"; return 1; }
  code=$(curl -sk --resolve "grafana.platform.local:443:$ip" -o /dev/null -w '%{http_code}' \
    --max-time 20 https://grafana.platform.local/login)
  [ "$code" = "200" ] && echo "reachable over HTTPS (HTTP $code)" || { echo "unexpected HTTP $code"; return 1; }
}

echo "checking the platform on EKS:"
check "Argo CD applications"           apps_ready
check "nodes running on spot capacity" nodes_are_spot
check "secret store (Pod Identity)"    store_valid
check "secret from Secrets Manager"    secret_synced
check "gateway load balancer"          gateway_address
check "Grafana behind the gateway"     grafana_through_gateway

exit $failed
