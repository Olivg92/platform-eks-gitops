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

REVISION="${1:?usage: $0 <branch> [namespace]}"
NS="${2:-argocd}"
ROOT_APP="root-local"

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

echo "done. Run 'make local-bootstrap' to hand control back to git after merging."
