#!/usr/bin/env bash
# Shared by local-up.sh, aws-up.sh and aws-down.sh: run each step quietly, keep
# everything it prints in a log file, and show that log only when a step fails. Terraform
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

# step "label" [--progress function] [--detail function] command...
# --progress prints a few words on how far the step is: shown next to the
# elapsed time, and kept on the final line. --detail prints lines to show under
# the step while it runs, such as each application Argo CD is waiting for: they
# go away when the step succeeds, and stay when it fails, since they then say
# what is stuck.
step() {
  local label="$1" progress="" detail="" started=$SECONDS watcher="" rc=0 lines
  shift
  while [ "${1:-}" = "--progress" ] || [ "${1:-}" = "--detail" ]; do
    case "$1" in
      --progress) progress="$2" ;;
      --detail) detail="$2" ;;
    esac
    shift 2
  done
  echo "==> $label" >> "$LOG"

  if [ "$VERBOSE" = 1 ]; then
    echo "==> $label"
    # `|| rc=...` rather than a bare command: the callers run with `set -e`, which
    # would otherwise end the script here, before the failure is reported.
    "$@" 2>&1 | tee -a "$LOG" || rc=${PIPESTATUS[0]}
  else
    # A live display only makes sense on a terminal; a pipe gets the final line.
    local stop="$LOG.stop"
    if [ -t 1 ]; then
      rm -f "$stop"
      (
        shown=0
        while :; do
          # Back to the top of what the previous round drew, then over it.
          if [ "$shown" -gt 0 ]; then printf '\033[%dA' "$shown"; fi
          printf '\r  %-46s %7s  %s\033[J' "$label" "$(duration $((SECONDS - started)))" "$([ -n "$progress" ] && "$progress")"
          shown=0
          if [ -n "$detail" ]; then
            lines=$("$detail")
            if [ -n "$lines" ]; then
              printf '\n%s' "$lines"
              shown=$(( $(printf '%s\n' "$lines" | wc -l) ))
            fi
          fi
          for _ in 1 2 3 4 5; do
            [ -f "$stop" ] && break 2
            sleep 0.2
          done
        done
        if [ "$shown" -gt 0 ]; then printf '\033[%dA' "$shown"; fi
        printf '\r\033[J'
      ) &
      watcher=$!
    fi
    "$@" >> "$LOG" 2>&1 || rc=$?
    if [ -n "$watcher" ]; then
      # Ask the display to finish its round and wipe itself, rather than kill it
      # halfway through a list and leave the end of it on the screen.
      touch "$stop"
      wait "$watcher" 2>/dev/null || true
      rm -f "$stop"
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    printf '  %-46s %7s  ok  %s\n' "$label" "$(duration $((SECONDS - started)))" "$([ -n "$progress" ] && "$progress")"
    return 0
  fi
  printf '  %-46s %7s  FAILED\n' "$label" "$(duration $((SECONDS - started)))"
  if [ -n "$detail" ]; then
    lines=$("$detail")
    if [ -n "$lines" ]; then printf '%s\n' "$lines"; fi
  fi
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

# Each application, in install order: a check mark when it is synced and
# healthy, otherwise what it is waiting on. Read from the file that
# scripts/wait-for-apps.sh rewrites at each poll when APPS_STATUS_FILE is set.
apps_detail() {
  [ -n "${APPS_STATUS_FILE:-}" ] && [ -s "$APPS_STATUS_FILE" ] || return 0
  local ok="ok" waiting=".."
  if [ "$(locale charmap 2>/dev/null)" = "UTF-8" ]; then
    ok="✓"
    waiting="…"
  fi
  awk -F'\t' -v ok="$ok" -v waiting="$waiting" '
    $2 == 1 { printf "      %s  %s\n", ok, $1; next }
            { printf "      %s  %-26s %s\n", waiting, $1, $3 }' "$APPS_STATUS_FILE"
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
