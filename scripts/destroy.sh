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
cluster="lab-commit-eks"
alb_group="lab-commit"
alb_prefix="k8s-labcommit"

echo "account: $(aws sts get-caller-identity --query Account --output text)"
echo "region:  $region"
echo "cluster: $cluster"
echo "this deletes the Argo CD applications, the ingresses of ALB group ${alb_group} and the ALB, then destroys: ${stacks[*]}"
read -r -p "type 'destroy lab-commit' to continue: " answer
if [[ "$answer" != "destroy lab-commit" ]]; then
  echo "aborted"
  exit 1
fi

KUBECONFIG="$(mktemp)"
export KUBECONFIG
trap 'rm -f "$KUBECONFIG"' EXIT

if aws eks describe-cluster --region "$region" --name "$cluster" >/dev/null 2>&1; then
  public="$(aws eks describe-cluster --region "$region" --name "$cluster" \
    --query cluster.resourcesVpcConfig.endpointPublicAccess --output text)"
  if [[ "$public" != "True" ]]; then
    echo "the API endpoint of $cluster is private only; re-enable it first:" >&2
    echo "  terraform -chdir=terraform/20-eks apply -var public_endpoint=true" >&2
    exit 1
  fi
  aws eks update-kubeconfig --region "$region" --name "$cluster" --kubeconfig "$KUBECONFIG" >/dev/null

  if kubectl get namespace argocd >/dev/null 2>&1; then
    echo "deleting Argo CD applications"
    kubectl -n argocd delete application root --ignore-not-found --wait=true --timeout=10m
    kubectl -n argocd delete application lab --ignore-not-found --wait=true --timeout=10m
  fi

  echo "deleting ingresses of ALB group ${alb_group}"
  kubectl get ingress --all-namespaces \
    -o jsonpath="{range .items[?(@.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name=='${alb_group}')]}{.metadata.namespace}{' '}{.metadata.name}{'\n'}{end}" |
    while read -r namespace name; do
      [[ -z "$name" ]] && continue
      kubectl -n "$namespace" delete ingress "$name" --wait=true --timeout=10m
    done
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

repos=()
eks_dir="$root/terraform/20-eks"
terraform -chdir="$eks_dir" init -input=false -backend-config=backend.hcl >/dev/null
for prefix in $(terraform -chdir="$eks_dir" state list 2>/dev/null |
  sed -n -E 's/^aws_ecr_pull_through_cache_rule\.this\["(.+)"\]$/\1/p'); do
  while read -r repo; do
    [[ -n "$repo" ]] && repos+=("$repo")
  done < <(aws ecr describe-repositories --region "$region" \
    --query "repositories[?starts_with(repositoryName, '${prefix}/')].repositoryName" --output text | tr '\t' '\n')
done
while read -r src; do
  [[ -z "$src" ]] && continue
  path="${src#*/}"
  repos+=("mirror/${path%%:*}")
done < "$root/scripts/mirror-images.txt"

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
for repo in ${repos[@]+"${repos[@]}"}; do
  if aws ecr delete-repository --region "$region" --repository-name "$repo" --force >/dev/null 2>&1; then
    echo "  deleted $repo"
  fi
done

echo "done"
