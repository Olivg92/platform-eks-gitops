#!/usr/bin/env bash
# Fails when a base image pinned in a Dockerfile is older than a given number of days.
#
#   check-base-age.sh <Dockerfile> <max-age-days>
#
# Chainguard rebuilds its images every day, so the pinned digest differs from the
# published one almost all the time: comparing the two would fail every run. The
# age of the pinned build is the useful signal. Dependabot proposes a bump every
# week, so a pin older than two weeks means it missed at least one: the silent
# failure described in docs/adr/0011.
#
# Reads the registry API directly with an anonymous pull token: no Docker daemon,
# no extra tool, the same answer locally and in CI.
set -euo pipefail

dockerfile="$1"
max_days="$2"
accept='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json'
now=$(date -u +%s)
stale=0

get() { curl -fsSL -H "Authorization: Bearer $token" -H "Accept: $accept" "https://cgr.dev/v2/$repo/$1"; }

pins=$(grep -oE '^FROM[[:space:]]+cgr\.dev/[^[:space:]]+@sha256:[0-9a-f]{64}' "$dockerfile" | awk '{print $2}' || true)
if [ -z "$pins" ]; then
  echo "no cgr.dev image pinned by digest in $dockerfile" >&2
  exit 1
fi

for pin in $pins; do
  image=${pin%@*}                # cgr.dev/chainguard/python:latest
  digest=${pin#*@}               # sha256:...
  repo=${image#cgr.dev/}
  repo=${repo%:*}                # chainguard/python
  token=$(curl -fsS "https://cgr.dev/token?scope=repository:$repo:pull" | jq -r .token)

  # The digest names a multi-platform index; the build date lives in the config
  # of one platform's image. The nodes and CI runners are amd64.
  manifest=$(get "manifests/$digest" | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')
  config=$(get "manifests/$manifest" | jq -r .config.digest)
  created=$(get "blobs/$config" | jq -r .created)

  age_days=$(( (now - $(date -u -d "$created" +%s)) / 86400 ))
  if [ "$age_days" -gt "$max_days" ]; then
    printf 'STALE  %s built %s, %d day(s) ago, limit %d\n' "$image" "$created" "$age_days" "$max_days"
    stale=1
  else
    printf 'ok     %s built %s, %d day(s) ago\n' "$image" "$created" "$age_days"
  fi
done

if [ "$stale" -ne 0 ]; then
  echo "A pinned base image is stale: Dependabot has not bumped it. See docs/adr/0011." >&2
  exit 1
fi
