#!/usr/bin/env bash
# Destroys the AWS demo environment, in the order that actually leaves nothing behind.
#
# Terraform does not know about the load balancers Kubernetes creates: they are
# made by a controller inside the cluster, not by the state file. Destroying the
# VPC before they are gone fails, and worse, a load balancer that outlives its
# cluster keeps billing quietly. So Kubernetes objects go first.
#
# One line per step, everything else in a file under logs/ (VERBOSE=1 streams
# it). The question comes before anything is touched, on a summary of the plan.
set -euo pipefail

# AWS only: the EKS cluster's own kubeconfig, written by `make up`.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/platform-eks-gitops-aws}"

TF_DIR="${TF_DIR:-terraform/envs/demo}"
PLAN=down.tfplan

# The stack requires the allowed API range, on purpose: nothing should create a
# cluster without saying who may reach it. Destroying does not care about the
# value, so give it an inert one rather than leaving the teardown blocked.
export TF_VAR_api_public_access_cidrs='["127.0.0.1/32"]'
# No default profile, for the same reason as in the Makefile: tearing down the
# wrong account is not a mistake a default should make possible.
: "${AWS_PROFILE:?set AWS_PROFILE, or run this through make}"
PROFILE="$AWS_PROFILE"
REGION="${AWS_REGION:-eu-north-1}"

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

start_log down
started=$SECONDS
trap 'rm -f "$TF_DIR/$PLAN"' EXIT

step "Terraform init" terraform -chdir="$TF_DIR" init -backend-config=backend.hcl -input=false -no-color
scripts/tf-recover.sh "$TF_DIR"
step "Terraform plan of the destroy" terraform -chdir="$TF_DIR" plan -destroy -input=false -no-color -out="$PLAN"

summary=$(plan_summary "$TF_DIR" "$PLAN")
TF_TOTAL=$(tail -n 1 <<<"$summary")

if [ "$TF_TOTAL" -eq 0 ]; then
  echo "  nothing left in the Terraform state"
else
  echo
  echo "Terraform plan:"
  sed '$d' <<<"$summary"
  echo
  if ! confirm "Destroy it?"; then
    echo "cancelled, nothing was touched"
    exit 1
  fi
  echo
fi

# Argo CD reconciles what it is told to reconcile, including during a teardown:
# delete the Gateway and it recreates it, and Envoy Gateway orders a brand new
# load balancer. Stop the controller first, or terraform waits forever on a VPC
# that Kubernetes keeps filling back up.
stop_argocd() {
  kubectl scale statefulset argocd-application-controller -n argocd --replicas=0 || true
  kubectl rollout status statefulset argocd-application-controller -n argocd --timeout=60s || true
}

remove_kubernetes_owned() {
  kubectl delete gateway --all -A --ignore-not-found --timeout=120s || true
  kubectl delete svc -A --field-selector spec.type=LoadBalancer --ignore-not-found --timeout=120s || true
  for _ in $(seq 1 30); do
    remaining=$(aws elbv2 describe-load-balancers --profile "$PROFILE" --region "$REGION" \
      --query "length(LoadBalancers[?VpcId!=null])" --output text 2>/dev/null || echo 0)
    [ "$remaining" = "0" ] && return 0
    sleep 10
  done
  echo "load balancers are still there after five minutes"
  return 1
}

cluster=$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || true)
if [ -n "$cluster" ] && kubectl config current-context 2>/dev/null | grep -q "$cluster"; then
  step "Stopping Argo CD, so it stops recreating" stop_argocd
  step "Removing the load balancer Kubernetes made" remove_kubernetes_owned
else
  echo "  no kubeconfig pointing at a running cluster, skipping the Kubernetes cleanup"
fi

if [ "$TF_TOTAL" -ne 0 ]; then
  if ! step "Terraform destroy" --progress tf_progress terraform -chdir="$TF_DIR" apply -input=false -no-color "$PLAN"; then
    if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
      # The checks below would all answer "?": say what happened instead.
      echo
      echo "the AWS session ended during the destroy, so part of the environment is still there," >&2
      echo "and still billing. Open a new session, then run this again: it picks up where it stopped." >&2
      echo "  make aws-login && make down" >&2
      exit 1
    fi
    echo "terraform destroy failed. What is still running:" >&2
  fi
fi

echo
echo "checking nothing is left behind:"
leftovers=0
check() { # label, query
  count=$(eval "$2" 2>/dev/null || echo "?")
  if [ "$count" = "0" ]; then
    printf '  ok    %-22s none\n' "$1"
  else
    printf '  CHECK %-22s %s\n' "$1" "$count"
    leftovers=1
  fi
}
check "load balancers" "aws elbv2 describe-load-balancers --profile $PROFILE --region $REGION --query 'length(LoadBalancers)' --output text"
check "classic load balancers" "aws elb describe-load-balancers --profile $PROFILE --region $REGION --query 'length(LoadBalancerDescriptions)' --output text"
check "elastic IPs" "aws ec2 describe-addresses --profile $PROFILE --region $REGION --query 'length(Addresses)' --output text"
check "EBS volumes" "aws ec2 describe-volumes --profile $PROFILE --region $REGION --query 'length(Volumes)' --output text"
check "EKS clusters" "aws eks list-clusters --profile $PROFILE --region $REGION --query 'length(clusters)' --output text"
check "NAT gateways" "aws ec2 describe-nat-gateways --profile $PROFILE --region $REGION --query \"length(NatGateways[?State!='deleted'])\" --output text"

if [ "$leftovers" -ne 0 ]; then
  echo
  echo "something is still running and still billing. Look at it before closing the laptop." >&2
  echo "log: $LOG" >&2
  exit 1
fi
# The cluster is gone, so are its credentials. They live in a file of their own,
# so removing it cannot touch any other cluster the machine knows about.
rm -f "$KUBECONFIG"

echo
echo "Everything is gone, in $(duration $((SECONDS - started))). The state bucket is the only resource left, and it costs cents."
