#!/usr/bin/env bash
set -euo pipefail

bucket="${1:-}"
region="${2:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
key="${CHROME_KEY:-chrome/googlechromestandaloneenterprise64.msi}"
url="${CHROME_URL:-https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi}"

if [[ -z "$bucket" || -z "$region" ]]; then
  echo "usage: $0 <installers-bucket> <region>" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "downloading $url"
curl -fsSL -o "$workdir/chrome.msi" "$url"

if [[ "$(head -c 4 "$workdir/chrome.msi" | od -An -tx1 | tr -d ' ')" != "d0cf11e0" ]]; then
  echo "downloaded file is not an MSI package" >&2
  exit 1
fi

echo "uploading to s3://$bucket/$key"
aws s3 cp --region "$region" --only-show-errors "$workdir/chrome.msi" "s3://$bucket/$key"
echo "done"
