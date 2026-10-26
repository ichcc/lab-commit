#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="$root/charts/lab/values-aws.yaml"

out() {
  terraform -chdir="$root/terraform/$1" output -raw "$2"
}

zone="$(out 50-edge zone_name)"

cat > "$target" <<VALUES
image:
  registry: $(out 20-eks ecr_registry)
zone: ${zone%.}
backend:
  roleArn: $(out 40-data backend_role_arn)
db:
  host: $(out 40-data db_endpoint)
  secretArn: $(out 40-data db_secret_arn)
ingress:
  certificateArn: $(out 50-edge certificate_arn)
  securityGroupId: $(out 10-network alb_security_group_id)
publicIngress:
  enabled: true
  securityGroupId: $(out 10-network admin_alb_security_group_id)
VALUES

echo "wrote $target"
cat "$target"
