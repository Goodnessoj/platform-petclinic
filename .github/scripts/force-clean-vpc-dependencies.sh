#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ENV="${DEPLOY_ENV:-dev}"
AWS_REGION="${AWS_REGION:-us-east-2}"
TF_WORKING_DIR="${TF_WORKING_DIR:-terraform/environments/${DEPLOY_ENV}}"
TF_VARS_FILE="${TF_VARS_FILE:-terraform.tfvars}"
CLUSTER_NAME="${CLUSTER_NAME:-petclinic-${DEPLOY_ENV}-eks}"
APP_NAMESPACE="${APP_NAMESPACE:-petclinic-${DEPLOY_ENV}}"
VPC_ID="${VPC_ID:-}"

DESTROY_ARGS=(
  -input=false
  -auto-approve
  -lock-timeout=5m
)

if [ -f "$TF_WORKING_DIR/$TF_VARS_FILE" ]; then
  DESTROY_ARGS+=(-var-file="$TF_VARS_FILE")
fi

state_has() {
  local address="$1"

  terraform -chdir="$TF_WORKING_DIR" state list 2>/dev/null | grep -Fxq "$address"
}

force_delete_namespace_pods() {
  local namespace="$1"

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    return 0
  fi

  while read -r pod_name; do
    if [ -n "${pod_name:-}" ]; then
      kubectl delete "$pod_name" \
        --namespace "$namespace" \
        --force \
        --grace-period=0 || true
    fi
  done < <(kubectl get pods \
    --namespace "$namespace" \
    -o name 2>/dev/null || true)
}

delete_load_balancers_in_vpc() {
  local vpc_id="$1"

  if [ -z "$vpc_id" ]; then
    return 0
  fi

  while read -r load_balancer_arn; do
    if [ -n "${load_balancer_arn:-}" ] && [ "$load_balancer_arn" != "None" ]; then
      echo "Deleting leftover load balancer: $load_balancer_arn"
      aws elbv2 delete-load-balancer \
        --region "$AWS_REGION" \
        --load-balancer-arn "$load_balancer_arn" || true
    fi
  done < <(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn" \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

if aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" >/dev/null 2>&1 || true

  if kubectl auth can-i get namespaces >/dev/null 2>&1; then
    for namespace in "$APP_NAMESPACE" argocd monitoring tracing; do
      force_delete_namespace_pods "$namespace"
    done
  fi
fi

if [ -z "$VPC_ID" ]; then
  VPC_ID="$(terraform -chdir="$TF_WORKING_DIR" output -raw vpc_id 2>/dev/null || true)"
fi

if [ -z "$VPC_ID" ]; then
  VPC_ID="$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=tag:Name,Values=petclinic-${DEPLOY_ENV}-vpc" "Name=tag:Project,Values=petclinic" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || true)"
fi

if [ "$VPC_ID" = "None" ]; then
  VPC_ID=""
fi

delete_load_balancers_in_vpc "$VPC_ID"

if state_has "module.eks.aws_eks_node_group.main"; then
  echo "Destroying EKS node group before retrying full destroy."
  terraform -chdir="$TF_WORKING_DIR" destroy \
    "${DESTROY_ARGS[@]}" \
    -target=module.eks.aws_eks_node_group.main
fi
