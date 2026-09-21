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

NS="${1:-argocd}"
TIMEOUT="${2:-600}"
INTERVAL=10
stable=0
deadline=$(( SECONDS + TIMEOUT ))

summarize() {
  kubectl get applications -n "$NS" -o json | python3 -c '
import json, sys
ready = watched = 0
pending = []
for app in json.load(sys.stdin)["items"]:
    if not (app["spec"].get("syncPolicy") or {}).get("automated"):
        continue  # paused on purpose
    watched += 1
    status = app.get("status", {})
    sync = status.get("sync", {}).get("status", "Unknown")
    health = status.get("health", {}).get("status", "Unknown")
    name = app["metadata"]["name"]
    if sync == "Synced" and health == "Healthy":
        ready += 1
    else:
        pending.append(f"{name} ({sync}/{health})")
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
    echo "  $ready/$watched ready: $pending"
  fi
  sleep "$INTERVAL"
done

echo "timed out after ${TIMEOUT}s. Current state:" >&2
kubectl get applications -n "$NS" >&2
exit 1
