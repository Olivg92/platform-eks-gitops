#!/usr/bin/env bash
# Creates the AWS demo environment, then installs the platform on it.
#
# One line per step, with how long it took. Everything the tools print goes to
# a file under logs/, shown only if a step fails (VERBOSE=1 streams it instead).
# Before anything is created, a summary of the plan and the hourly cost, and a
# question: Terraform then applies that saved plan, not a new one.
set -euo pipefail

: "${AWS_PROFILE:?set AWS_PROFILE, or run this through make}"
: "${KUBECONFIG:?set KUBECONFIG, or run this through make, which does}"
TF_DIR="${TF_DIR:-terraform/envs/demo}"
REGION="${AWS_REGION:-eu-north-1}"
MAKE="${MAKE:-make}"
PLAN=up.tfplan

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Nothing creates a cluster without saying who may reach its API: here, the
# machine running this, and only it.
if ! [[ "${MY_IP:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "could not detect the public address of this machine: pass it, as in make up MY_IP=203.0.113.4" >&2
  exit 1
fi
export TF_VAR_api_public_access_cidrs="[\"$MY_IP/32\"]"

start_log up
started=$SECONDS
trap 'rm -f "$TF_DIR/$PLAN"' EXIT

step "Terraform init" terraform -chdir="$TF_DIR" init -backend-config=backend.hcl -input=false -no-color
scripts/tf-recover.sh "$TF_DIR"
step "Terraform plan" terraform -chdir="$TF_DIR" plan -input=false -no-color -out="$PLAN"

summary=$(plan_summary "$TF_DIR" "$PLAN")
TF_TOTAL=$(tail -n 1 <<<"$summary")

if [ "$TF_TOTAL" -eq 0 ]; then
  echo "  the infrastructure already matches the code, nothing to apply"
else
  echo
  echo "Terraform plan:"
  sed '$d' <<<"$summary"
  echo "The Kubernetes API will answer to $MY_IP/32 only."
  echo "This costs about \$0.18 an hour, until \`make down\`."
  echo
  if ! confirm "Apply it?"; then
    echo "cancelled, nothing was changed"
    exit 1
  fi
  echo
  step "Terraform apply" --progress tf_progress terraform -chdir="$TF_DIR" apply -input=false -no-color "$PLAN"
fi

write_kubeconfig() {
  local cluster
  cluster=$(terraform -chdir="$TF_DIR" output -raw cluster_name)
  aws eks update-kubeconfig --region "$REGION" --name "$cluster" --kubeconfig "$KUBECONFIG"
}

step "Credentials for the new cluster" write_kubeconfig
step "Argo CD" "$MAKE" --no-print-directory aws-argocd
step "Root application" "$MAKE" --no-print-directory aws-bootstrap
step "Platform, synced by Argo CD" --progress apps_progress "$MAKE" --no-print-directory aws-wait

echo
echo "The platform is up, in $(duration $((SECONDS - started))). Log: $LOG"
"$MAKE" --no-print-directory aws-info
