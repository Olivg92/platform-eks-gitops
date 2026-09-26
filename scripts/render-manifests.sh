#!/usr/bin/env bash
# Renders every kustomization under gitops/ and validates the result.
# Run by CI, and runnable locally before pushing: same command, same answer.
set -euo pipefail

KUSTOMIZE="${KUSTOMIZE:-kustomize build}"
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
      failed=1
    fi
  else
    printf '  FAIL  %s (does not render)\n' "$dir"
    echo "$output" | sed 's/^/        /'
    failed=1
  fi
done < <(find gitops -name kustomization.yaml -exec dirname {} \; | sort)

echo "rendered $count kustomizations"
exit $failed
