#!/usr/bin/env bash
# Renders every kustomization under gitops/ and validates the result.
# Run by CI, and runnable locally before pushing: same command, same answer.
set -euo pipefail

# kubectl embeds kustomize, so the standalone binary is optional: CI installs
# it, and a laptop with kubectl alone runs the same check.
if [ -z "${KUSTOMIZE:-}" ]; then
  if command -v kustomize >/dev/null 2>&1; then
    KUSTOMIZE="kustomize build"
  else
    KUSTOMIZE="kubectl kustomize"
  fi
fi
command -v kubeconform >/dev/null 2>&1 || {
  echo "kubeconform is not installed, see: make check-tools GROUP=dev" >&2
  exit 1
}

failed=0
count=0

while IFS= read -r dir; do
  count=$((count + 1))
  if output=$($KUSTOMIZE "$dir" 2>&1); then
    if echo "$output" | kubeconform -strict -ignore-missing-schemas -summary - >/dev/null 2>&1; then
      printf '  ok    %s\n' "$dir"
    else
      printf '  FAIL  %s (rendered, but invalid)\n' "$dir"
      echo "$output" | kubeconform -strict -ignore-missing-schemas - | sed 's/^/        /'
      failed=$((failed + 1))
    fi
  else
    printf '  FAIL  %s (does not render)\n' "$dir"
    echo "$output" | sed 's/^/        /'
    failed=$((failed + 1))
  fi
done < <(find gitops -name kustomization.yaml -exec dirname {} \; | sort)

# The last line is the one people read: it must not announce a success that the
# lines above contradict.
if [ "$failed" -ne 0 ]; then
  echo "$failed of $count kustomizations failed" >&2
  exit 1
fi
echo "rendered $count kustomizations"
