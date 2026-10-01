#!/usr/bin/env bash
# Says which tools are installed, grouped by what they are for: running the
# platform locally needs far less than deploying it on AWS or contributing.
#
#   check-tools.sh [local|aws|dev|all]
#
# The local group is always required. The aws and dev groups are reported, and
# required only when asked for. QUIET=1 prints nothing unless something is
# missing, which is how the AWS targets call it.
set -uo pipefail

want="${1:-local}"
quiet="${QUIET:-0}"
missing=0
report=""

say() { report+="$1"$'\n'; }

version_of() {
  case "$1" in
    docker)      docker --version 2>/dev/null | sed -E 's/^Docker version ([^,]+).*/\1/' ;;
    k3d)         k3d version 2>/dev/null | awk 'NR==1 {print $3}' ;;
    kubectl)     kubectl version --client 2>/dev/null | awk '/Client Version/ {print $3}' ;;
    helm)        helm version --short 2>/dev/null ;;
    python3)     python3 --version 2>/dev/null | awk '{print $2}' ;;
    curl)        curl --version 2>/dev/null | awk 'NR==1 {print $2}' ;;
    terraform)   terraform version 2>/dev/null | awk 'NR==1 {print $2}' ;;
    aws)         aws --version 2>/dev/null | awk '{print $1}' | cut -d/ -f2 ;;
    pre-commit)  pre-commit --version 2>/dev/null | awk '{print $2}' ;;
    tflint)      tflint --version 2>/dev/null | awk 'NR==1 {print $3}' ;;
    checkov)     checkov --version 2>/dev/null ;;
    kubeconform) kubeconform -v 2>/dev/null ;;
  esac
}

group() { # title, required (yes|no), tools...
  local title="$1" required="$2"; shift 2
  say "$title"
  for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
      say "$(printf '  ok       %-12s %s' "$tool" "$(version_of "$tool")")"
    elif [ "$required" = yes ]; then
      say "$(printf '  MISSING  %s' "$tool")"
      missing=1
    else
      say "$(printf '  absent   %-12s not needed for the local platform' "$tool")"
    fi
  done
}

required() { [ "$want" = "$1" ] || [ "$want" = all ] && echo yes || echo no; }

group "local platform (make local-up):" yes docker k3d kubectl helm python3 curl
# Installed is not enough: k3d needs a daemon it is allowed to talk to.
if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
  say "  MISSING  the Docker daemon does not answer: is it running, and may this user use it?"
  missing=1
fi
group "AWS demo (make up):" "$(required aws)" terraform aws
group "contributing (make lint):" "$(required dev)" pre-commit tflint checkov kubeconform

if [ "$missing" -ne 0 ]; then
  printf '%s' "$report"
  echo "some required tools are missing"
  exit 1
fi
if [ "$quiet" != 1 ]; then
  printf '%s' "$report"
  echo "everything needed is there"
fi
