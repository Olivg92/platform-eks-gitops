#!/usr/bin/env bash
# Drives the demo API so the SLOs have something to measure.
#
#   demo-traffic.sh load [seconds] [rps]   steady traffic through the gateway
#   demo-traffic.sh break [error_rate] [latency_ms]
#   demo-traffic.sh fix                    back to healthy
#   demo-traffic.sh status                 what the API is currently doing
#
# Everything goes through the gateway, so the measured path is the real one.
set -uo pipefail

NS="${DEMO_NS:-demo}"
HOST="${DEMO_HOST:-demo.platform.local}"
PORT="${DEMO_PORT:-8443}"
BASE="https://${HOST}:${PORT}"
CURL=(curl -sk --resolve "${HOST}:${PORT}:127.0.0.1" --max-time 10)

case "${1:-load}" in
  load)
    seconds="${2:-60}"; rps="${3:-5}"
    echo "sending ~${rps} req/s to ${BASE}/ for ${seconds}s"
    deadline=$(( SECONDS + seconds ))
    sent=0; failed=0
    while (( SECONDS < deadline )); do
      for _ in $(seq 1 "$rps"); do
        code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${BASE}/")
        sent=$(( sent + 1 ))
        [ "$code" = "200" ] || failed=$(( failed + 1 ))
      done
      sleep 1
    done
    echo "sent ${sent} requests, ${failed} of them failed"
    ;;

  break|fix)
    if [ "$1" = fix ]; then rate=0; latency=0; else rate="${2:-0.3}"; latency="${3:-0}"; fi
    echo "setting error_rate=${rate} latency_ms=${latency} on every pod"
    # The setting lives in each pod's memory, so going through the gateway would
    # only reach one replica and the injection would be half applied. Talk to
    # every pod directly instead.
    for pod in $(kubectl get pods -n "$NS" -l app.kubernetes.io/name=demo-api -o name); do
      kubectl exec -n "$NS" "$pod" -- python -c "
import json, urllib.request
body = json.dumps({'error_rate': ${rate}, 'latency_ms': ${latency}}).encode()
req = urllib.request.Request('http://localhost:8000/chaos', data=body,
                             headers={'content-type': 'application/json'}, method='POST')
print('  ${pod##*/}:', urllib.request.urlopen(req).read().decode())"
    done
    ;;

  status)
    for pod in $(kubectl get pods -n "$NS" -l app.kubernetes.io/name=demo-api -o name); do
      printf '  %s: ' "${pod##*/}"
      kubectl exec -n "$NS" "$pod" -- python -c "
import urllib.request
print(urllib.request.urlopen('http://localhost:8000/chaos').read().decode())"
    done
    ;;

  *)
    echo "usage: $0 {load|break|fix|status}" >&2; exit 1
    ;;
esac
