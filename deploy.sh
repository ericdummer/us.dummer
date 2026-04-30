#!/usr/bin/env bash
set -euo pipefail

# Usage: ./deploy.sh
# Deploys ./content to the www website bucket. Requires [dummer-deploy]
# profile in ~/.aws/credentials (created by bootstrap.sh).

DOMAIN="${DOMAIN:-dummer.us}"
BUCKET="${BUCKET:-www.${DOMAIN}}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
BUILD_DIR="${1:-./content}"
PROFILE="${AWS_PROFILE:-dummer-deploy}"
AWS=(aws --profile "$PROFILE" --region "$REGION")

if [ ! -d "$BUILD_DIR" ]; then
  echo "ERROR: Build directory not found: $BUILD_DIR"
  echo "Usage: ./deploy.sh <build-dir>"
  exit 1
fi

echo "==> Deploying $BUILD_DIR to s3://$BUCKET ..."
"${AWS[@]}" s3 sync "$BUILD_DIR" "s3://$BUCKET" \
  --delete \
  --only-show-errors

echo "==> Done."
echo "    Website bucket: http://${BUCKET}.s3-website-${REGION}.amazonaws.com"
echo "    Public URL:      https://www.${DOMAIN#www.}"
