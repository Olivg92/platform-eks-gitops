#!/usr/bin/env bash
# Puts a Terraform stack back in a usable state after a run that was cut short,
# typically by AWS credentials expiring halfway (docs/runbooks). Such a run
# leaves two things behind: `errored.tfstate`, the state it could not upload,
# and its lock in the state bucket.
#
#   tf-recover.sh <terraform directory>
#
# Does nothing when there is nothing to recover. Refuses to remove a lock unless
# it is provably the leftover of a dead run from this machine: unlocking a run
# that is still alive lets two processes write the same state.
set -euo pipefail

: "${AWS_PROFILE:?set AWS_PROFILE, or run this through make}"
tf_dir="${1:?usage: $0 <terraform directory>}"
backend="$tf_dir/backend.hcl"
errored="$tf_dir/errored.tfstate"

setting() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$backend" | head -1; }
bucket=$(setting bucket)
key=$(setting key)
region=$(setting region)

lock=$(aws s3 cp "s3://$bucket/$key.tflock" - --region "$region" --profile "$AWS_PROFILE" 2>/dev/null || true)

if [ -z "$lock" ] && [ ! -f "$errored" ]; then
  exit 0
fi
echo "a previous run on this stack was interrupted, recovering before going on:"

if [ -n "$lock" ]; then
  read -r lock_id lock_who lock_created < <(python3 -c '
import json, sys
lock = json.load(sys.stdin)
print(lock["ID"], lock["Who"], lock["Created"])' <<<"$lock")
  me="$(id -un)@$(hostname)"

  if pgrep -x terraform >/dev/null; then
    echo "  a terraform process is running on this machine: let it finish, or stop it, then retry" >&2
    exit 1
  fi
  if [ "$lock_who" != "$me" ]; then
    echo "  the state is locked by $lock_who since $lock_created, and this machine is $me." >&2
    echo "  Removing someone else's lock is not a decision for a script. If that run is dead:" >&2
    echo "    terraform -chdir=$tf_dir force-unlock $lock_id" >&2
    exit 1
  fi
  echo "  removing the lock that run left behind ($lock_created)"
  terraform -chdir="$tf_dir" force-unlock -force "$lock_id" >/dev/null
fi

if [ -f "$errored" ]; then
  # Terraform refuses the push when the bucket already holds a newer state, in
  # which case the file is stale and the error says so: nothing is overwritten.
  echo "  uploading the state that run could not save"
  terraform -chdir="$tf_dir" state push errored.tfstate
  rm "$errored"
fi
echo "  recovered"
