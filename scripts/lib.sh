#!/usr/bin/env bash
# Shared by aws-up.sh and aws-down.sh: run each step quietly, keep everything it
# prints in a log file, and show that log only when a step fails. Terraform
# alone prints hundreds of lines for a cluster; what a person needs is which
# step is running, for how long, and whether it worked.
#
# VERBOSE=1 streams everything instead, as the tools print it.

LOG_DIR="${LOG_DIR:-logs}"
VERBOSE="${VERBOSE:-0}"

start_log() { # name
  mkdir -p "$LOG_DIR"
  LOG="$LOG_DIR/$1-$(date +%Y%m%d-%H%M%S).log"
  : > "$LOG"
}

duration() {
  if [ "$1" -ge 60 ]; then
    printf '%dm%02ds' $(($1 / 60)) $(($1 % 60))
  else
    printf '%ds' "$1"
  fi
}

# step "label" [--progress function] command...
# The optional function prints a few words about how far the step is, read
# from the log: it is shown next to the elapsed time, and kept on the last line.
step() {
  local label="$1" progress="" started=$SECONDS watcher="" rc=0
  shift
  if [ "$1" = "--progress" ]; then
    progress="$2"
    shift 2
  fi
  echo "==> $label" >> "$LOG"

  if [ "$VERBOSE" = 1 ]; then
    echo "==> $label"
    # `|| rc=...` rather than a bare command: the callers run with `set -e`, which
    # would otherwise end the script here, before the failure is reported.
    "$@" 2>&1 | tee -a "$LOG" || rc=${PIPESTATUS[0]}
  else
    # A live line only makes sense on a terminal; a pipe gets the final one.
    if [ -t 1 ]; then
      (
        while true; do
          printf '\r  %-46s %7s  %s\033[K' "$label" "$(duration $((SECONDS - started)))" "$([ -n "$progress" ] && "$progress")"
          sleep 1
        done
      ) &
      watcher=$!
    fi
    "$@" >> "$LOG" 2>&1 || rc=$?
    if [ -n "$watcher" ]; then
      kill "$watcher" 2>/dev/null || true
      wait "$watcher" 2>/dev/null || true
      printf '\r\033[K'
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    printf '  %-46s %7s  ok  %s\n' "$label" "$(duration $((SECONDS - started)))" "$([ -n "$progress" ] && "$progress")"
    return 0
  fi
  printf '  %-46s %7s  FAILED\n' "$label" "$(duration $((SECONDS - started)))"
  if [ "$VERBOSE" != 1 ]; then
    # Only what this step printed: the steps before it worked, and are noise here.
    echo
    echo "what it printed (the last 30 lines):"
    awk -v marker="==> $label" '$0 == marker { start = NR } { line[NR] = $0 }
      END { for (i = start + 1; i <= NR; i++) print line[i] }' "$LOG" | tail -n 30 | sed 's/^/    /'
  fi
  echo
  echo "full log: $LOG"
  return "$rc"
}

# What a saved plan would do, in a few lines instead of a few hundred: how many
# resources per action, and of which types. Prints the total on the last line.
plan_summary() { # terraform directory, plan file
  terraform -chdir="$1" show -json "$2" | python3 -c '
import collections, json, sys, textwrap

verbs = {"create": "create", "update": "change", "replace": "replace", "delete": "destroy"}
kinds = {action: collections.Counter() for action in verbs}
for rc in json.load(sys.stdin).get("resource_changes", []):
    actions = rc["change"]["actions"]
    if actions in (["no-op"], ["read"]):
        continue
    action = "replace" if len(actions) == 2 else actions[0]
    kinds[action][rc["type"]] += 1

total = 0
for action, verb in verbs.items():
    count = sum(kinds[action].values())
    if not count:
        continue
    total += count
    # "\0" keeps each count with its type when the line wraps.
    types = ", ".join(f"{n}\0{kind}" for kind, n in sorted(kinds[action].items()))
    print(f"  to {verb}: {count}")
    print(textwrap.fill(types, width=92, initial_indent="    ", subsequent_indent="    ").replace("\0", " "))
print(total)'
}

# How far an apply is, counted from what Terraform has reported so far.
TF_TOTAL=0
tf_progress() {
  local finished
  finished=$(grep -cE '(Creation|Modifications|Destruction) complete' "$LOG" 2>/dev/null || true)
  echo "${finished:-0} of $TF_TOTAL resources"
}

# How far Argo CD is, from the last line scripts/wait-for-apps.sh printed.
apps_progress() {
  grep -oE '[0-9]+/[0-9]+ ready|all [0-9]+ applications' "$LOG" | tail -n 1 |
    sed -E 's|all ([0-9]+) applications|\1/\1 ready|'
}

# Asks for the one word that commits to the operation. Anything else cancels,
# an absent answer included, so a script cannot approve by accident.
confirm() { # question
  local answer=""
  printf "%s Only 'yes' will be accepted: " "$1"
  read -r answer || true
  # A person ends the line by pressing Enter; a pipe does not.
  [ -t 0 ] || echo
  [ "$answer" = "yes" ]
}
