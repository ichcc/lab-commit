#!/usr/bin/env bash
set -euo pipefail

region="${1:-${AWS_REGION:-}}"
if [[ -z "$region" ]]; then
  echo "usage: $0 <region>" >&2
  exit 1
fi

dir="$(cd "$(dirname "$0")" && pwd)"
account="$(aws sts get-caller-identity --query Account --output text)"
host="${account}.dkr.ecr.${region}.amazonaws.com"

aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$host"

while read -r src; do
  [[ -z "$src" ]] && continue
  path="${src#*/}"
  repo="mirror/${path%%:*}"
  tag="${path##*:}"
  if ! aws ecr describe-repositories --region "$region" --repository-names "$repo" >/dev/null 2>&1; then
    aws ecr create-repository --region "$region" --repository-name "$repo" >/dev/null
  fi
  docker buildx imagetools create --tag "${host}/${repo}:${tag}" "$src"
done < "$dir/mirror-images.txt"
