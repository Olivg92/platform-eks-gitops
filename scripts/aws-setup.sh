#!/usr/bin/env bash
# First time on AWS: chooses the profile and the region, opens a session, and
# writes the files `make up` needs, so that the next command can be `make up`.
#
# Safe to run again. It never overwrites a file: it fills in what is missing,
# checks what is there, and says what it decided and why.
set -euo pipefail

TF_DIR=terraform/envs/demo
BOOTSTRAP=terraform/bootstrap
LOCAL_MK=local.mk
# The default of the Makefile and of the Terraform variables.
DEFAULT_REGION=eu-north-1
BUCKET_PREFIX="${BUCKET_PREFIX:-platform-eks-gitops-tfstate-}"
# Zones where EKS does not create clusters, by zone id, since zone names differ
# from one account to the next (docs.aws.amazon.com/eks/latest/userguide/network-reqs.html).
EKS_EXCLUDED_ZONES=" use1-az3 usw1-az2 cac1-az3 "

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

say() { printf '  %-18s %s\n' "$1" "$2"; }
fail() { printf '\n%s\n' "$1" >&2; exit 1; }
in_list() { [ -n "$1" ] && [[ " $2 " == *" $1 "* ]]; } # word, words
count() { wc -w <<<"$1" | tr -d ' '; }
setting() { # file, key: the value of `key = "value"` in a Terraform file
  [ -f "$1" ] || return 0
  sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" | head -n 1
}
mk_setting() { # key: its value in local.mk
  [ -f "$LOCAL_MK" ] || return 0
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$1[[:space:]]*[:?]*=[[:space:]]*([^[:space:]#]+).*/\2/p" "$LOCAL_MK" | tail -n 1
}
ask() { # question: prints the answer typed
  local answer=""
  printf '%s' "$1" >&2
  read -r answer || true
  # A person ends the line by pressing Enter; a pipe does not.
  [ -t 0 ] || echo >&2
  printf '%s' "$answer"
}
remember() { # key, value: added to local.mk, which make reads on every run
  if [ -s "$LOCAL_MK" ] && [ -n "$(tail -c 1 "$LOCAL_MK")" ]; then echo >> "$LOCAL_MK"; fi
  printf '%s := %s\n' "$1" "$2" >> "$LOCAL_MK"
}

echo "AWS setup of the demo environment:"

# --- The profile ------------------------------------------------------------------
note=""
if [ -z "${AWS_PROFILE:-}" ]; then
  echo
  echo "Which AWS CLI profile should this project use? It is kept in $LOCAL_MK, which is not committed."
  profiles=$(aws configure list-profiles 2>/dev/null | tr '\n' ' ' || true)
  if [ -n "$profiles" ]; then echo "Profiles on this machine: ${profiles% }"; fi
  AWS_PROFILE=$(ask "Profile (a new name is created at the login): ")
  [[ "${AWS_PROFILE:-}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "no valid profile name given, nothing was changed"
  remember AWS_PROFILE "$AWS_PROFILE"
  note=" (now in $LOCAL_MK)"
  echo
fi
export AWS_PROFILE
say "profile" "$AWS_PROFILE$note"

# --- The session ------------------------------------------------------------------
uses_login() { [ -n "$(aws configure get login_session --profile "$AWS_PROFILE" 2>/dev/null)" ]; }
profile_exists() { in_list "$AWS_PROFILE" "$(aws configure list-profiles 2>/dev/null | tr '\n' ' ')"; }
profile_region=$(aws configure get region --profile "$AWS_PROFILE" 2>/dev/null || true)

if session=$(scripts/aws-session.sh check 10 2>/dev/null); then
  session=${session#AWS session }
  say "session" "${session:-credentials work}"
elif uses_login || ! profile_exists; then
  # A login without a region asks for one first. Give it the profile's, or the
  # default, which the detection below corrects if the account works elsewhere.
  login_region=${profile_region:-$DEFAULT_REGION}
  echo
  echo "Opening an AWS session for profile $AWS_PROFILE: sign in on the page the browser opens."
  LOGIN_REGION=$login_region scripts/aws-session.sh login || {
    # 3: the AWS CLI is too old, which the login has just said.
    if [ $? -eq 3 ]; then exit 1; fi
    fail "no session was opened. If this account works in another region than $login_region, set
that one on the profile first, then run make aws-setup again:
  aws configure set region <its region> --profile $AWS_PROFILE"
  }
  echo
  profile_region=$(aws configure get region --profile "$AWS_PROFILE" 2>/dev/null || true)
else
  fail "profile $AWS_PROFILE has no working credentials. Renew them the way this profile gets them
(aws sso login, a new access key...), then run make aws-setup again."
fi

account=$(aws sts get-caller-identity --query Account --output text)
say "account" "$account"

# --- The region, when it is already decided ------------------------------------------
tfvars="$TF_DIR/terraform.tfvars"
backend="$TF_DIR/backend.hcl"
bucket=$(setting "$backend" bucket)
bucket_region=$(setting "$backend" region)
region=$(mk_setting AWS_REGION) reason="set in $LOCAL_MK"
if [ -z "$region" ] && [ -n "${AWS_REGION:-}" ]; then
  region=$AWS_REGION reason="from the AWS_REGION variable"
fi
if [ -z "$region" ]; then
  region=$(setting "$tfvars" region) reason="set in $tfvars"
fi
if [ -z "$region" ]; then
  region=$bucket_region reason="where the state bucket is"
fi

# --- Which regions answer -----------------------------------------------------------
# No call says which region an account is meant for. Asking each region for its
# zones does: an account restricted to one region, as those of the new AWS
# sign-up are, answers in that one and refuses everywhere else. The answers
# also give the zones to choose from. A region already decided only needs
# checking, along with the default region of the profile.
probe=$(mktemp -d)
trap 'rm -rf "$probe" "$BOOTSTRAP/setup.tfplan"' EXIT
if [ -n "$region" ]; then
  regions=$region
  if [ -n "$profile_region" ] && [ "$profile_region" != "$region" ]; then regions+=" $profile_region"; fi
else
  regions=""
  for r in us-east-1 ${profile_region:-} "$DEFAULT_REGION"; do
    regions=$(aws ec2 describe-regions --region "$r" --query 'Regions[].RegionName' --output text 2>/dev/null) && break
  done
  [ -n "$regions" ] || fail "no region answers: may profile $AWS_PROFILE call EC2 at all?"
fi
(
  # In parallel, with the current credentials passed as variables, which take
  # precedence over the profile: otherwise each call could try to renew the
  # session at the same moment.
  if creds=$(aws configure export-credentials --format env 2>/dev/null); then eval "$creds"; fi
  for r in $regions; do
    aws ec2 describe-availability-zones --region "$r" \
      --filters Name=zone-type,Values=availability-zone Name=state,Values=available \
      --query 'AvailabilityZones[].[ZoneName,ZoneId]' --output text > "$probe/$r" 2>/dev/null ||
      rm -f "$probe/$r" &
  done
  wait
)
allowed=""
for f in "$probe"/*; do
  if [ -e "$f" ]; then allowed+="${f##*/} "; fi
done
allowed=${allowed% }
if [ -n "$region" ] && ! in_list "$region" "$allowed"; then
  fail "region $region ($reason) does not answer for this account. Fix that setting, or remove it
so that make aws-setup finds the region itself."
fi
[ -n "$allowed" ] || fail "no region lists its zones: may profile $AWS_PROFILE call EC2?"

# --- The state bucket ---------------------------------------------------------------
if [ -z "$bucket" ]; then
  # Any region this account answers in will do: the list of buckets is global.
  s3_region=${allowed%% *}
  found=$(aws s3api list-buckets --region "$s3_region" \
    --query "Buckets[?starts_with(Name, '$BUCKET_PREFIX')].Name" --output text | tr '\t' ' ')
  found=${found//None/}
  case "$(count "$found")" in
    0) ;;
    1) bucket=${found// /} ;;
    *)
      echo
      echo "Several state buckets in this account: $found"
      bucket=$(ask "Which one holds the state of this project? ")
      in_list "$bucket" "$found" || fail "not one of them, nothing was changed"
      ;;
  esac
  if [ -n "$bucket" ]; then
    bucket_region=$(aws s3api get-bucket-location --bucket "$bucket" --region "$s3_region" \
      --query LocationConstraint --output text)
    # S3 answers "None" for the oldest region, which predates the field.
    if [ "$bucket_region" = "None" ]; then bucket_region=us-east-1; fi
  fi
fi

# --- The region, and why --------------------------------------------------------------
if [ -z "$region" ] && [ -n "$bucket_region" ]; then
  region=$bucket_region reason="where the state bucket is"
fi
if [ -z "$region" ] && [ "$(count "$allowed")" = 1 ]; then
  region=$allowed reason="the only region this account allows"
fi
if [ -z "$region" ]; then
  default=$DEFAULT_REGION
  if in_list "$profile_region" "$allowed"; then default=$profile_region; fi
  echo
  echo "This account works in $(count "$allowed") regions. Prices and latency differ, and the data stays where it is created."
  region=$(ask "Region for the demo [$default]: ")
  region=${region:-$default} reason="chosen"
fi
in_list "$region" "$allowed" || fail "region $region ($reason) is not one this account allows: $allowed"

note=""
if [ -z "$(mk_setting AWS_REGION)" ]; then
  remember AWS_REGION "$region"
  note=" (now in $LOCAL_MK)"
fi
say "region" "$region, $reason$note"

# The default region of the profile serves outside this project too: fill it in
# when there is none, and correct it when it names a region the account refuses.
if [ "$profile_region" != "$region" ]; then
  if [ -z "$profile_region" ] || ! in_list "$profile_region" "$allowed"; then
    aws configure set region "$region" --profile "$AWS_PROFILE"
    say "" "now also the default region of profile $AWS_PROFILE${profile_region:+, instead of $profile_region}"
  fi
fi

# --- The settings of the demo environment ------------------------------------------------
if [ -f "$tfvars" ]; then
  written=$(setting "$tfvars" account_id)
  if [ "$written" != "$account" ]; then
    fail "$tfvars names account ${written:-none}, but profile $AWS_PROFILE is account $account.
Terraform would refuse to run on either. Fix the profile or the file: nothing was changed."
  fi
  tf_region=$(setting "$tfvars" region)
  if [ "${tf_region:-$DEFAULT_REGION}" != "$region" ]; then
    fail "$tfvars deploys in ${tf_region:-$DEFAULT_REGION}, not in $region. Set region and
availability_zones in it to match ($TF_DIR/README.md says how), then run make aws-setup again."
  fi
  say "terraform.tfvars" "kept, same account and region"
else
  zones=$(awk -v excluded="$EKS_EXCLUDED_ZONES" 'index(excluded, " " $2 " ") == 0 { print $1 }' "$probe/$region" |
    sort | head -n 2 | tr '\n' ' ')
  zones=${zones% }
  [ "$(count "$zones")" = 2 ] || fail "region $region has fewer than two zones EKS can use"
  {
    echo "# Written by \`make aws-setup\`. Not committed: the account id is not a secret,"
    echo "# but it does not belong in a public repository."
    echo "account_id         = \"$account\""
    echo "region             = \"$region\""
    printf 'availability_zones = ["%s", "%s"]\n' "${zones% *}" "${zones#* }"
  } > "$tfvars"
  say "terraform.tfvars" "written, zones $zones"
fi

# --- The state bucket, created if there is none ------------------------------------------
if [ -z "$bucket" ]; then
  name_file="$BOOTSTRAP/terraform.tfvars"
  if [ ! -f "$name_file" ]; then
    # Bucket names are unique across all of AWS: a random suffix keeps clear of taken ones.
    {
      echo "# Written by \`make aws-setup\`. Not committed."
      echo "account_id        = \"$account\""
      echo "state_bucket_name = \"${BUCKET_PREFIX}$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')\""
      echo "region            = \"$region\""
    } > "$name_file"
  fi
  bucket=$(setting "$name_file" state_bucket_name)
  [ -n "$bucket" ] || fail "$name_file sets no state_bucket_name: set one, or delete the file."
  bucket_region=$(setting "$name_file" region)
  bucket_region=${bucket_region:-$DEFAULT_REGION}
  echo
  echo "This account has no state bucket yet. Terraform keeps the state of the demo environment"
  echo "in one, created once by $BOOTSTRAP: $bucket, in $bucket_region,"
  echo "versioned, encrypted and private. It costs cents a month, and it is the one thing that"
  echo "stays between sessions."
  echo
  start_log aws-setup
  step "Terraform init (bootstrap)" terraform -chdir="$BOOTSTRAP" init -input=false -no-color
  step "Terraform plan (bootstrap)" terraform -chdir="$BOOTSTRAP" plan -input=false -no-color -out=setup.tfplan
  summary=$(plan_summary "$BOOTSTRAP" setup.tfplan)
  if [ "$(tail -n 1 <<<"$summary")" -gt 0 ]; then
    echo
    echo "Terraform plan:"
    sed '$d' <<<"$summary"
    echo
    confirm "Create it?" || fail "nothing was created. Run make aws-setup again when ready."
    echo
    step "Terraform apply (bootstrap)" terraform -chdir="$BOOTSTRAP" apply -input=false -no-color setup.tfplan
  fi
fi

# --- Where Terraform keeps the state of the demo ----------------------------------------
if [ -f "$backend" ]; then
  if aws s3api head-bucket --bucket "$bucket" --region "${bucket_region:-$region}" >/dev/null 2>&1; then
    say "backend.hcl" "kept, bucket $bucket found"
  else
    fail "$backend names bucket $bucket, which this account cannot reach. Fix the file, or delete it
and run make aws-setup again to find the right one."
  fi
else
  {
    echo "# Written by \`make aws-setup\`. Not committed: the bucket name belongs to one account."
    echo "bucket       = \"$bucket\""
    echo "key          = \"envs/demo/terraform.tfstate\""
    echo "region       = \"$bucket_region\""
    echo "encrypt      = true"
    echo "use_lockfile = true"
  } > "$backend"
  say "backend.hcl" "written, bucket $bucket"
fi

echo
echo "Ready. Next: make plan to see what would be created, or make up to create it."
