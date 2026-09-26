#!/usr/bin/env bash
# Turns `terraform plan` output into the pull request comment.
#
#   format-plan.sh <plan-output-file> <plan-exit-code> [value-to-redact]
#
# Exit codes are those of `terraform plan -detailed-exitcode`: 0 no change,
# 2 changes, anything else an error. The optional value is removed from the
# output before it is posted, which is how the account id stays out of a
# comment on a public repository.
set -euo pipefail

plan_file="$1"
code="$2"
redact="${3:-}"

body=$(cat "$plan_file")
if [ -n "$redact" ]; then
  body=${body//"$redact"/"<account-id>"}
fi

summary=$(grep -E '^(Plan:|No changes\.)' <<<"$body" | tail -1 || true)
case "$code" in
  0) status="No change to the infrastructure." ;;
  2) status="${summary:-Changes detected.}" ;;
  *) status="**The plan failed.** See the details below." ;;
esac

# GitHub rejects comments over 65536 characters. Keep the end of the plan,
# which is where the summary and any error live.
max=60000
if [ "${#body}" -gt "$max" ]; then
  body="(truncated, the full plan is in the workflow log)
${body: -$max}"
fi

cat <<MD
### Terraform plan, \`terraform/envs/demo\`

${status}

Planned with \`-refresh=false\`: this compares the configuration with the last applied state, which
is what a pull request changes. It does not query AWS for drift.

<details><summary>Full plan</summary>

\`\`\`
${body}
\`\`\`

</details>
MD
