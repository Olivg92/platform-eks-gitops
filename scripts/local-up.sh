#!/usr/bin/env bash
# Creates the local k3d cluster, then installs the whole platform on it.
#
# One line per step, with how long it took, as for `make up`. Everything the
# tools print (k3d, the image build, Helm, kubectl) goes to a file under logs/,
# shown only if a step fails; VERBOSE=1 streams it instead.
set -euo pipefail

: "${KUBECONFIG:?set KUBECONFIG, or run this through make, which does}"

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

start_log local-up
started=$SECONDS
export APPS_STATUS_FILE="$LOG.apps"
trap 'rm -f "$APPS_STATUS_FILE" "$APPS_STATUS_FILE.tmp"' EXIT

step "k3d cluster" make --no-print-directory local-cluster
step "Demo API image, built and imported" make --no-print-directory demo-image
step "Argo CD" make --no-print-directory local-argocd
step "Root application" make --no-print-directory local-bootstrap
step "Platform, synced by Argo CD" --progress apps_progress --detail apps_detail make --no-print-directory local-wait

echo
echo "The platform is up, in $(duration $((SECONDS - started))). Log: $LOG"
make --no-print-directory local-info
