#!/usr/bin/env bash
# An `aws login` session ends twelve hours after the login, and nothing on the
# machine says when: its cache only holds fifteen-minute credentials, renewed
# until the session dies. A teardown started too late stops halfway, with the
# cluster still billing (docs/runbooks). So the login time is written down here,
# and the long operations ask for it before they start.
#
#   aws-session.sh login          run `aws login`, then record when it happened
#   aws-session.sh check [hours]  fail unless the session is younger than that
#
# Profiles that get credentials another way (SSO, a role, access keys) are only
# checked for working: their lifetime is not something this script can know.
set -euo pipefail

: "${AWS_PROFILE:?set AWS_PROFILE, or run this through make}"
SESSION_HOURS=12
stamp="${XDG_STATE_HOME:-$HOME/.local/state}/platform-eks-gitops/aws-login-$AWS_PROFILE"

valid() { aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; }
uses_login() { [ -n "$(aws configure get login_session --profile "$AWS_PROFILE" 2>/dev/null)" ]; }
hm() { printf '%dh%02d' $(($1 / 3600)) $(($1 % 3600 / 60)); }

case "${1:-}" in
  login)
    aws login --profile "$AWS_PROFILE"
    valid || { echo "the login did not give profile $AWS_PROFILE working credentials" >&2; exit 1; }
    mkdir -p "$(dirname "$stamp")"
    date +%s > "$stamp"
    echo "session opened for profile $AWS_PROFILE, good for $SESSION_HOURS hours"
    ;;

  check)
    max_hours="${2:-10}"
    if ! valid; then
      echo "profile $AWS_PROFILE has no working AWS credentials." >&2
      echo "With \`aws login\`, open a session with: make aws-login" >&2
      exit 1
    fi
    uses_login || exit 0

    if [ ! -f "$stamp" ]; then
      echo "this AWS session was not opened with \`make aws-login\`, so its age is unknown," >&2
      echo "and it ends $SESSION_HOURS hours after the login. Open a fresh one first: make aws-login" >&2
      exit 1
    fi
    age=$(( $(date +%s) - $(cat "$stamp") ))
    if [ "$age" -gt $((max_hours * 3600)) ]; then
      echo "this AWS session was opened $(hm "$age") ago, and a session lasts $SESSION_HOURS hours:" >&2
      echo "not enough left to be sure of finishing. Open a fresh one first: make aws-login" >&2
      exit 1
    fi
    echo "AWS session opened $(hm "$age") ago, about $(hm $((SESSION_HOURS * 3600 - age))) left"
    ;;

  *)
    echo "usage: $0 login | check [max-age-hours]" >&2
    exit 2
    ;;
esac
