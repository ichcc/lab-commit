#!/usr/bin/env bash
set -euo pipefail

region="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
if [[ -z "$region" ]]; then
  echo "usage: $0 <region>" >&2
  exit 1
fi

vpc_id="$(aws ec2 describe-vpcs --region "$region" \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)"

if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
  echo "no default VPC in $region"
  exit 0
fi

echo "deleting default VPC $vpc_id in $region"

for igw in $(aws ec2 describe-internet-gateways --region "$region" \
  --filters Name=attachment.vpc-id,Values="$vpc_id" \
  --query 'InternetGateways[].InternetGatewayId' --output text); do
  aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc_id"
  aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw"
done

for subnet in $(aws ec2 describe-subnets --region "$region" \
  --filters Name=vpc-id,Values="$vpc_id" \
  --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --region "$region" --subnet-id "$subnet"
done

aws ec2 delete-vpc --region "$region" --vpc-id "$vpc_id"
echo "done"
