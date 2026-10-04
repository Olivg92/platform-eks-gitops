#!/usr/bin/env bash
# Wait until every auto-synced Argo CD Application is Synced and Healthy.
#
# `kubectl wait` is not enough here: a freshly created Application reports Healthy
# for a few seconds before its resources exist, so the wait would return too early.
# We poll instead and require the desired state twice in a row.
#
# Applications whose auto-sync is paused are skipped: while developing on a branch,
# scripts/dev-follow-revision.sh pauses the root application on purpose.
set -euo pipefail

# Shared by the local and AWS environments, so there is no safe default: refuse
# to fall back on ~/.kube/config, which may point at an unrelated cluster.
: "${KUBECONFIG:?set KUBECONFIG, or run this through make, which does}"

NS="${1:-argocd}"
TIMEOUT="${2:-600}"
INTERVAL=10
stable=0
last=""
deadline=$(( SECONDS + TIMEOUT ))

# With APPS_STATUS_FILE set, each poll also writes one line per application to
# that file, in install order: what `make local-up` and `make up` list on screen.
summarize() {
  kubectl get applications -n "$NS" -o json | python3 -c '
import json, os, sys
ready = watched = 0
pending = []
rows = []
for app in json.load(sys.stdin)["items"]:
    if not (app["spec"].get("syncPolicy") or {}).get("automated"):
        continue  # paused on purpose
    watched += 1
    status = app.get("status", {})
    sync = status.get("sync", {}).get("status") or "Unknown"
    health = status.get("health", {}).get("status") or "Unknown"
    name = app["metadata"]["name"]
    done = sync == "Synced" and health == "Healthy"
    if done:
        ready += 1
    else:
        pending.append(f"{name} ({sync}/{health})")
    try:
        wave = int((app["metadata"].get("annotations") or {}).get("argocd.argoproj.io/sync-wave", 0))
    except ValueError:
        wave = 0
    # The root application comes first: it is the one that creates the others.
    order = -1000 if name.startswith("root-") else wave
    rows.append((order, name, int(done), health if health != "Healthy" else sync))

path = os.environ.get("APPS_STATUS_FILE")
if path:
    with open(path + ".tmp", "w") as f:
        for _, name, done, state in sorted(rows):
            f.write(f"{name}\t{done}\t{state}\n")
    os.replace(path + ".tmp", path)
print(ready, watched, ", ".join(pending), sep="|")'
}

while (( SECONDS < deadline )); do
  IFS='|' read -r ready watched pending < <(summarize)

  if (( watched > 0 && ready == watched )); then
    stable=$(( stable + 1 ))
    if (( stable >= 2 )); then
      echo "all $watched applications are synced and healthy"
      exit 0
    fi
  else
    stable=0
    # Say it once per change, not every ten seconds.
    line="  $ready/$watched ready: $pending"
    if [ "$line" != "$last" ]; then
      echo "$line"
      last="$line"
    fi
  fi
  sleep "$INTERVAL"
done

echo "timed out after ${TIMEOUT}s. Current state:" >&2
kubectl get applications -n "$NS" >&2
exit 1
