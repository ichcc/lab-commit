#!/usr/bin/env bash
set -euo pipefail

region="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
include_bootstrap="${2:-}"
if [[ -z "$region" ]]; then
  echo "usage: $0 <region> [--with-bootstrap]" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
stacks=(70-pipeline 60-windows 50-edge 40-data 30-platform 20-eks 10-network)
[[ "$include_bootstrap" == "--with-bootstrap" ]] && stacks+=(00-bootstrap)
alb_prefix="k8s-labcommit"

echo "account: $(aws sts get-caller-identity --query Account --output text)"
echo "region:  $region"
echo "context: $(kubectl config current-context 2>/dev/null || echo none)"
echo "this deletes the Argo CD applications, all ingresses and the ALB, then destroys: ${stacks[*]}"
read -r -p "type 'destroy lab-commit' to continue: " answer
if [[ "$answer" != "destroy lab-commit" ]]; then
  echo "aborted"
  exit 1
fi

if kubectl get namespace argocd >/dev/null 2>&1; then
  echo "deleting Argo CD applications"
  kubectl -n argocd delete application root --ignore-not-found --wait=true --timeout=10m
  kubectl -n argocd delete application lab --ignore-not-found --wait=true --timeout=10m
fi

if kubectl version --request-timeout=10s >/dev/null 2>&1; then
  echo "deleting remaining ingresses"
  kubectl delete ingress --all --all-namespaces --wait=true --timeout=10m
fi

echo "waiting for load balancers named ${alb_prefix}* to disappear"
for _ in $(seq 1 60); do
  count="$(aws elbv2 describe-load-balancers --region "$region" \
    --query "length(LoadBalancers[?starts_with(LoadBalancerName, '${alb_prefix}')])" --output text)"
  [[ "$count" == "0" ]] && break
  echo "  $count left"
  sleep 10
done
if [[ "$count" != "0" ]]; then
  echo "load balancers still exist, stop here and check the controller logs" >&2
  exit 1
fi

for stack in "${stacks[@]}"; do
  dir="$root/terraform/$stack"
  echo "destroying $stack"
  extra=()
  [[ "$stack" == "50-edge" ]] && extra=(-var alb_ready=false)
  if [[ "$stack" == "00-bootstrap" ]]; then
    terraform -chdir="$dir" init -input=false >/dev/null
  else
    terraform -chdir="$dir" init -input=false -backend-config=backend.hcl >/dev/null
  fi
  terraform -chdir="$dir" destroy -auto-approve -input=false ${extra[@]+"${extra[@]}"}
done

echo "deleting cache and mirror repositories in ECR"
for repo in $(aws ecr describe-repositories --region "$region" \
  --query "repositories[?starts_with(repositoryName, 'mirror/') || starts_with(repositoryName, 'ecr-public/') || starts_with(repositoryName, 'k8s/') || starts_with(repositoryName, 'quay/')].repositoryName" \
  --output text); do
  aws ecr delete-repository --region "$region" --repository-name "$repo" --force >/dev/null
  echo "  deleted $repo"
done

echo "done"
