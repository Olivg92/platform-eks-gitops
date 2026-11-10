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

# What the root is doing: "refreshing" until the controller has consumed the
# last refresh request, "syncing" while a sync operation is queued or running,
# "failed" if the last one did not succeed, and its sync status otherwise.
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
elif phase in ("Failed", "Error"):
    print("failed")
else:
    print(status.get("sync", {}).get("status") or "Unknown")'
}

# Makes the controller reconcile the root once more, then waits for any sync
# operation that reconcile started to end. The controller consumes the
# annotation at the end of a reconcile that read it, and never reconciles one
# application twice at the same time: once it is gone, no reconcile that read
# the root before this call is still running. Pass "hard" to also make it read
# git again rather than its cache.
settle_root() {
  kubectl annotate application "$ROOT_APP" -n "$NS" \
    "argocd.argoproj.io/refresh=${1:-normal}" --overwrite >/dev/null
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

# Auto-sync refuses a sync that would prune every resource the application
# manages, which is what a source that renders nothing asks for ("auto-sync
# will wipe out all resources"), unless the policy sets allowEmpty. A sync
# started by hand has no such guard: from a branch that emptied
# gitops/envs/<env>, the root would prune every application, and through their
# finalizers everything they deployed, on EKS as well. Apply the same rule to
# the same input: status.resources is the list the controller hands to that
# check, written by the same comparison with git. An empty list counts as
# emptied, as it does there. Reads the root as JSON on stdin and its sync
# policy as JSON in $1, so it can be tried on a crafted root without a cluster.
check_not_emptied() {
  POLICY="$1" python3 -c '
import json, os, sys
app = json.load(sys.stdin)
status = app.get("status") or {}
resources = status.get("resources") or []
if (json.loads(os.environ["POLICY"]).get("automated") or {}).get("allowEmpty") \
        or any(not r.get("requiresPruning") for r in resources):
    sys.exit(0)
name = app["metadata"]["name"]
source = app["spec"].get("source") or {}
where = "%s at %s" % (source.get("path"), source.get("targetRevision"))
# A render that failed looks the same: Argo CD then compares with no manifest
# at all, so every live resource requires pruning. Refuse too, as auto-sync
# does (the sync status is Unknown), but do not call it empty nor suggest
# allowEmpty: a typo in the path or a repo-server error is not a reason to
# allow wiping the platform. Say what failed instead.
errors = [c for c in status.get("conditions") or []
          if c.get("type") in ("ComparisonError", "InvalidSpecError")]
if errors:
    print("Argo CD could not render %s for %s, not syncing it:" % (where, name),
          file=sys.stderr)
    for c in errors:
        print("  %s: %s" % (c["type"], c.get("message")), file=sys.stderr)
    sys.exit(1)
effect = ("prune every resource it manages (%d)" % len(resources)) if resources \
    else "leave it empty"
print("%s renders nothing from %s: a sync would %s. Refusing, as auto-sync"
      " does: set spec.syncPolicy.automated.allowEmpty to true on it if that is"
      " intended." % (name, where, effect), file=sys.stderr)
sys.exit(1)'
}

# Pausing removes spec.syncPolicy.automated, and allowEmpty with it: keep the
# policy as applied from git, for the sync below.
policy=$(kubectl get application "$ROOT_APP" -n "$NS" -o json | python3 -c '
import json, sys
print(json.dumps(json.load(sys.stdin)["spec"].get("syncPolicy") or {}))')

# The root application must run first: it is what creates the other
# applications. Sync it from here rather than through auto-sync. On a cluster
# where an earlier run repointed them, auto-sync can only self-heal them back
# to main, and each self-heal waits longer: from the end of the last
# operation, Argo CD waits 2 s x 3^(n-1), up to 5 minutes, where n is the
# self-heal count of the last operation, then stores n+1. By the seventh run in
# a row, the root waited longer than this script does. A sync started by hand
# is not a self-heal: it starts at once, and resets that count to 0.
echo "pausing auto-sync on $ROOT_APP so it does not revert the patches"
kubectl patch application "$ROOT_APP" -n "$NS" --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null

# Pausing stops the next automated sync, not one already decided. The
# controller works from a cached copy of the root, which can lag behind the
# pause: a reconcile still holding the old copy can start a self-heal once the
# sync or the patches below have begun, and put every application it finds
# OutOfSync back on main. Go on only once the controller has seen the pause
# and that sync, if any, has ended. Argo CD caches git state too: have it read
# the branch again rather than wait a minute.
settle_root hard

# The reconcile settle_root waited for compared the root with the branch, so
# its status says what a sync would do now. Refusing leaves the root paused,
# which prunes nothing but would surprise whoever looks at it next: say so,
# and how to undo it (root-local and root-aws come from local- and
# aws-bootstrap).
if ! kubectl get application "$ROOT_APP" -n "$NS" -o json | check_not_emptied "$policy"; then
  echo "$ROOT_APP is left paused on $REVISION: 'make ${ROOT_APP#root-}-bootstrap' hands it back to main" >&2
  exit 1
fi

# A sync started by hand does not read the sync policy: give it the options
# auto-sync would use. That includes the retry strategy: the policy's own if it
# sets one, 5 attempts otherwise, as the controller does.
echo "syncing $ROOT_APP so it creates its applications"
operation=$(POLICY="$policy" python3 -c '
import json, os
policy = json.loads(os.environ["POLICY"])
retry = policy.get("retry")
print(json.dumps({"operation": {
    "initiatedBy": {"username": "dev-follow-revision"},
    "sync": {"prune": True, "syncOptions": policy.get("syncOptions", [])},
    "retry": retry if retry is not None else {"limit": 5},
}}))')
kubectl patch application "$ROOT_APP" -n "$NS" --type merge -p "$operation" >/dev/null

# The root creates its applications wave by wave, in one sync. Patching before
# that sync ends leaves the last wave created after the patches below, still
# tracking main: counting the applications that exist is not enough, as the
# demo-api on EKS once showed. Wait until the sync has ended and the root is
# Synced, which only holds once every application it declares exists.
for _ in $(seq 1 90); do
  state=$(root_state)
  case "$state" in
    Synced|failed) break ;;
  esac
  sleep 2
done
if [ "$state" != "Synced" ]; then
  echo "$ROOT_APP did not finish creating its applications (state: $state)" >&2
  kubectl get application "$ROOT_APP" -n "$NS" \
    -o jsonpath='{.status.operationState.message}{"\n"}' >&2
  exit 1
fi

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
