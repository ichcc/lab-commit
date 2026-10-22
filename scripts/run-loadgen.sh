#!/usr/bin/env bash
set -euo pipefail

region="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
zone="${2:-lab.internal}"
if [[ -z "$region" ]]; then
  echo "usage: $0 <region> [zone]" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
account="$(aws sts get-caller-identity --query Account --output text)"
source_image="$(grep -E '/grafana/k6:' "$root/scripts/mirror-images.txt" | head -n 1)"
if [[ -z "$source_image" ]]; then
  echo "grafana/k6 is missing from scripts/mirror-images.txt" >&2
  exit 1
fi
path="${source_image#*/}"
image="${account}.dkr.ecr.${region}.amazonaws.com/mirror/${path}"
target="https://lab-commit-task.${zone}/"

kubectl -n lab delete job k6-load --ignore-not-found --wait=true
kubectl -n lab create configmap k6-script --from-file=script.js="$root/loadgen/script.js" \
  --dry-run=client -o yaml | kubectl apply -f -
sed -e "s|K6_IMAGE|${image}|" -e "s|TARGET_URL_VALUE|${target}|" "$root/loadgen/job.yaml" | kubectl apply -f -

echo "load test started against $target with $image"
echo "follow:  kubectl -n lab logs -f job/k6-load"
echo "scaling: kubectl -n lab get pods -l app.kubernetes.io/name=frontend -w"
