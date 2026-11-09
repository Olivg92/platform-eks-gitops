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

# What the root is doing: "refreshing" until the controller has consumed the
# last refresh request, "syncing" while a sync operation is queued or running,
# and its sync status once it is idle.
root_state() {
  kubectl get application "$ROOT_APP" -n "$NS" -o json | python3 -c '
import json, sys
app = json.load(sys.stdin)
status = app.get("status", {})
phase = (status.get("operationState") or {}).get("phase")
if "argocd.argoproj.io/refresh" in (app["metadata"].get("annotations") or {}):
    print("refreshing")
elif app.get("operation") or phase in ("Running", "Terminating"):
    print("syncing")
else:
    print(status.get("sync", {}).get("status") or "Unknown")'
}

# Makes the controller reconcile the root once more, then waits for any sync
# operation that reconcile started to end. The controller consumes the
# annotation at the end of a reconcile that read it, and never reconciles one
# application twice at the same time: once it is gone, no reconcile that read
# the root before this call is still running.
settle_root() {
  kubectl annotate application "$ROOT_APP" -n "$NS" \
    argocd.argoproj.io/refresh=normal --overwrite >/dev/null
  for _ in $(seq 1 90); do
    state=$(root_state)
    case "$state" in
      refreshing|syncing) sleep 2 ;;
      *) return 0 ;;
    esac
  done
  echo "$ROOT_APP did not settle (still $state)" >&2
  exit 1
}

# Argo CD caches git state, so ask for a fresh read instead of waiting a minute.
kubectl annotate application "$ROOT_APP" -n "$NS" \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null

# The root creates its applications wave by wave, in one sync. Pausing it before
# that sync ends leaves the last wave created after the patches below, still
# tracking main: counting the applications that exist is not enough, as the
# demo-api on EKS once showed. Wait until the root is Synced, which only holds
# once every application it declares exists, and no longer syncing: right after
# that sync it self-heals the last wave, and reports Synced while it does.
for _ in $(seq 1 90); do
  state=$(root_state)
  if [ "$state" = "Synced" ]; then
    break
  fi
  sleep 2
done
if [ "$state" != "Synced" ]; then
  echo "$ROOT_APP did not finish creating its applications (state: $state)" >&2
  exit 1
fi

echo "pausing auto-sync on $ROOT_APP so it does not revert the patches"
kubectl patch application "$ROOT_APP" -n "$NS" --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null

# Pausing stops the next automated sync, not one already decided. The
# controller works from a cached copy of the root, which can lag behind the
# pause: a reconcile still holding the old copy can start a self-heal once the
# patches below have begun, and put every application it finds OutOfSync back
# on main. Patch only once the controller has seen the pause and that sync, if
# any, has ended.
settle_root

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

# The patches leave the root OutOfSync, the very state it self-heals from. Have
# it reconcile once more, paused, so that the check below comes after any sync
# that could still revert them, not before.
settle_root

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
