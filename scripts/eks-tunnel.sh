#!/usr/bin/env bash
set -euo pipefail

region="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
port="${2:-8443}"
if [[ -z "$region" ]]; then
  echo "usage: $0 <region> [local-port]" >&2
  exit 1
fi

cluster="lab-commit-eks"
kubeconfig="${LAB_KUBECONFIG:-$HOME/.kube/lab-commit-tunnel}"

endpoint="$(aws eks describe-cluster --region "$region" --name "$cluster" --query cluster.endpoint --output text)"
host="${endpoint#https://}"
instance="$(aws ec2 describe-instances --region "$region" \
  --filters Name=tag:Name,Values=lab-commit-windows Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
if [[ "$instance" == "None" || -z "$instance" ]]; then
  echo "instance lab-commit-windows is not running, start it first" >&2
  exit 1
fi

mkdir -p "$(dirname "$kubeconfig")"
aws eks update-kubeconfig --region "$region" --name "$cluster" --kubeconfig "$kubeconfig" --alias lab-commit-tunnel >/dev/null
cluster_arn="$(aws eks describe-cluster --region "$region" --name "$cluster" --query cluster.arn --output text)"
kubectl config --kubeconfig "$kubeconfig" set-cluster "$cluster_arn" \
  --server "https://127.0.0.1:${port}" --tls-server-name "$host" >/dev/null

echo "tunnel 127.0.0.1:${port} -> ${host}:443 through ${instance}"
echo "kubectl:   export KUBECONFIG=${kubeconfig}"
echo "terraform: terraform -chdir=terraform/30-platform plan -var api_tunnel_port=${port}"
echo "stop with Ctrl-C"

exec aws ssm start-session --region "$region" --target "$instance" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=${host},portNumber=443,localPortNumber=${port}"
