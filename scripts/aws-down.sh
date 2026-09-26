#!/usr/bin/env bash
# Destroys the AWS demo environment, in the order that actually leaves nothing behind.
#
# Terraform does not know about the load balancers Kubernetes creates: they are
# made by a controller inside the cluster, not by the state file. Destroying the
# VPC before they are gone fails, and worse, a load balancer that outlives its
# cluster keeps billing quietly. So Kubernetes objects go first.
set -uo pipefail

# AWS only: the EKS cluster's own kubeconfig, written by `make up`.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/platform-eks-gitops-aws}"

TF_DIR="${TF_DIR:-terraform/envs/demo}"

# The stack requires the allowed API range, on purpose: nothing should create a
# cluster without saying who may reach it. Destroying does not care about the
# value, so give it an inert one rather than leaving the teardown blocked.
export TF_VAR_api_public_access_cidrs='["127.0.0.1/32"]'
PROFILE="${AWS_PROFILE:-perso}"
REGION="${AWS_REGION:-eu-north-1}"

cluster=$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || true)

if [ -n "$cluster" ] && kubectl config current-context 2>/dev/null | grep -q "$cluster"; then
  # Argo CD reconciles what it is told to reconcile, including during a teardown:
  # delete the Gateway and it recreates it, and Envoy Gateway orders a brand new
  # load balancer. Stop the controller first, or terraform waits forever on a VPC
  # that Kubernetes keeps filling back up.
  echo "stopping the Argo CD controller so it stops recreating what we delete..."
  kubectl scale statefulset argocd-application-controller -n argocd --replicas=0 2>/dev/null || true
  kubectl rollout status statefulset argocd-application-controller -n argocd --timeout=60s 2>/dev/null || true

  echo "removing Kubernetes objects that own AWS resources..."
  kubectl delete gateway --all -A --ignore-not-found --timeout=120s 2>/dev/null || true
  kubectl delete svc -A --field-selector spec.type=LoadBalancer --ignore-not-found --timeout=120s 2>/dev/null || true

  echo "waiting for the load balancers to disappear..."
  for _ in $(seq 1 30); do
    remaining=$(aws elbv2 describe-load-balancers --profile "$PROFILE" --region "$REGION" \
      --query "length(LoadBalancers[?VpcId!=null])" --output text 2>/dev/null || echo 0)
    [ "$remaining" = "0" ] && break
    sleep 10
  done
else
  echo "no kubeconfig pointing at $cluster, skipping the Kubernetes cleanup"
fi

echo "destroying the Terraform stack (the refresh alone takes a couple of minutes)..."
AWS_PROFILE="$PROFILE" terraform -chdir="$TF_DIR" destroy -input=false

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
  exit 1
fi
# The cluster is gone, so are its credentials. They live in a file of their own,
# so removing it cannot touch any other cluster the machine knows about.
rm -f "$KUBECONFIG" && echo "removed the kubeconfig of the destroyed cluster"

echo
echo "everything is gone. The state bucket is the only resource left, and it costs cents."
