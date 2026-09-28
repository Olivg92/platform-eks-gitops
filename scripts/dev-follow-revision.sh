#!/usr/bin/env bash
# Development helper. NOT part of the GitOps flow.
#
# Applications committed to this repository always track `main`, which is the
# single source of truth. While developing on a branch those files do not exist
# on `main` yet, so this script repoints every Application at the branch under
# test and pauses the root application, which would otherwise revert them.
#
# Usage: scripts/dev-follow-revision.sh <branch> [namespace]
set -euo pipefail

# Shared by the local and AWS environments, so there is no safe default: refuse
# to fall back on ~/.kube/config, which may point at an unrelated cluster.
: "${KUBECONFIG:?set KUBECONFIG, or run this through make, which does}"

REVISION="${1:?usage: $0 <branch> [namespace]}"
NS="${2:-argocd}"
# Local and AWS have their own root application.
ROOT_APP="${ROOT_APP:-root-local}"

# The root application must run first: it is what creates the other applications.
# It may be paused from a previous run, so resume it before waiting for them.
echo "letting $ROOT_APP create its applications"
kubectl patch application "$ROOT_APP" -n "$NS" --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null

# Argo CD caches git state, so ask for a fresh read instead of waiting a minute.
kubectl annotate application "$ROOT_APP" -n "$NS" \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null

# The root creates its applications wave by wave, in one sync. Pausing it before
# that sync ends leaves the last wave created after the patches below, still
# tracking main: counting the applications that exist is not enough, as the
# demo-api on EKS once showed. Wait until the root is Synced, which only holds
# once every application it declares exists.
for _ in $(seq 1 90); do
  refreshing=$(kubectl get application "$ROOT_APP" -n "$NS" \
    -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/refresh}')
  sync=$(kubectl get application "$ROOT_APP" -n "$NS" -o jsonpath='{.status.sync.status}')
  if [ -z "$refreshing" ] && [ "$sync" = "Synced" ]; then
    break
  fi
  sleep 2
done
if [ "$sync" != "Synced" ]; then
  echo "$ROOT_APP did not finish creating its applications (sync: ${sync:-unknown})" >&2
  exit 1
fi

echo "pausing auto-sync on $ROOT_APP so it does not revert the patches"
kubectl patch application "$ROOT_APP" -n "$NS" --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null

for app in $(kubectl get applications -n "$NS" -o name | grep -v "/$ROOT_APP$"); do
  patch=$(kubectl get "$app" -n "$NS" -o json | REVISION="$REVISION" python3 -c '
import json, os, sys
spec = json.load(sys.stdin)["spec"]
rev = os.environ["REVISION"]
sources = spec.get("sources") or ([spec["source"]] if "source" in spec else [])
changed = False
for s in sources:
    # Only git sources track a branch; Helm sources track a chart version.
    if s.get("targetRevision") == "main" and "chart" not in s:
        s["targetRevision"] = rev
        changed = True
if not changed:
    sys.exit(1)
key = "sources" if "sources" in spec else "source"
print(json.dumps({"spec": {key: spec[key]}}))') || continue
  kubectl patch "$app" -n "$NS" --type merge -p "$patch" >/dev/null
  echo "  ${app#application.argoproj.io/} -> $REVISION"
done

# An application left on main would test main while claiming to test the
# branch. Fail loudly rather than let that pass.
left=$(kubectl get applications -n "$NS" -o json | ROOT_APP="$ROOT_APP" python3 -c '
import json, os, sys
for app in json.load(sys.stdin)["items"]:
    spec = app["spec"]
    sources = spec.get("sources") or ([spec["source"]] if "source" in spec else [])
    if app["metadata"]["name"] != os.environ["ROOT_APP"] and any(
            s.get("targetRevision") == "main" and "chart" not in s for s in sources):
        print(app["metadata"]["name"])')
if [ -n "$left" ]; then
  echo "still tracking main: $left" >&2
  exit 1
fi

echo "done. Run 'make local-bootstrap' to hand control back to git after merging."
