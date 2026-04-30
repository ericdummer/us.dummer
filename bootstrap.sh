#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-dummer.us}"
WWW_DOMAIN="${WWW_DOMAIN:-www.${DOMAIN}}"
BUCKET_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
IAM_USER="${IAM_USER:-us-dummer-deploy}"
IAM_POLICY_NAME="${IAM_POLICY_NAME:-us-dummer-deploy-policy}"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS=(aws --profile "$AWS_PROFILE" --region "$BUCKET_REGION")

create_bucket_if_missing() {
  local bucket="$1"

  echo "==> Ensuring bucket exists: $bucket"
  if "${AWS[@]}" s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    echo "    Bucket already exists."
    return
  fi

  if [ "$BUCKET_REGION" = "us-east-1" ]; then
    "${AWS[@]}" s3api create-bucket --bucket "$bucket"
  else
    "${AWS[@]}" s3api create-bucket \
      --bucket "$bucket" \
      --create-bucket-configuration LocationConstraint="$BUCKET_REGION"
  fi

  echo "    Created."
}

configure_public_website_bucket() {
  local bucket="$1"

  echo "==> Configuring static website bucket: $bucket"
  "${AWS[@]}" s3api put-bucket-website \
    --bucket "$bucket" \
    --website-configuration '{
      "IndexDocument": {"Suffix": "index.html"},
      "ErrorDocument": {"Key": "404.html"}
    }'

  "${AWS[@]}" s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration \
      "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

  local bucket_policy
  bucket_policy=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${bucket}/*"
    }
  ]
}
EOF
)

  "${AWS[@]}" s3api put-bucket-policy --bucket "$bucket" --policy "$bucket_policy"
  echo "    Done."
}

configure_redirect_bucket() {
  local bucket="$1"
  local target_host="$2"

  echo "==> Configuring redirect bucket: $bucket -> https://$target_host"
  "${AWS[@]}" s3api put-bucket-website \
    --bucket "$bucket" \
    --website-configuration "RedirectAllRequestsTo={HostName=${target_host},Protocol=https}"
  echo "    Done."
}

echo "==> Checking prerequisites..."
if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws cli not found. Install it: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
  exit 1
fi

echo "==> Resolving AWS account info..."
ACCOUNT_ID=$("${AWS[@]}" sts get-caller-identity --query Account --output text)
echo "    Account ID: $ACCOUNT_ID"
echo "    Region:     $BUCKET_REGION"
echo "    Profile:    $AWS_PROFILE"

create_bucket_if_missing "$WWW_DOMAIN"
create_bucket_if_missing "$DOMAIN"

configure_public_website_bucket "$WWW_DOMAIN"
configure_redirect_bucket "$DOMAIN" "$WWW_DOMAIN"

echo "==> Ensuring IAM user exists: $IAM_USER"
if "${AWS[@]}" iam get-user --user-name "$IAM_USER" >/dev/null 2>&1; then
  echo "    User already exists."
else
  "${AWS[@]}" iam create-user --user-name "$IAM_USER" >/dev/null
  echo "    Created."
fi

echo "==> Attaching deploy policy..."
DEPLOY_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListWebsiteBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${WWW_DOMAIN}"
      ]
    },
    {
      "Sid": "ManageWebsiteObjects",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${WWW_DOMAIN}/*"
      ]
    }
  ]
}
EOF
)

"${AWS[@]}" iam put-user-policy \
  --user-name "$IAM_USER" \
  --policy-name "$IAM_POLICY_NAME" \
  --policy-document "$DEPLOY_POLICY"
echo "    Done."

echo "==> Checking for existing access keys..."
KEY_COUNT=$("${AWS[@]}" iam list-access-keys \
  --user-name "$IAM_USER" \
  --query 'length(AccessKeyMetadata)' \
  --output text)

if [ "$KEY_COUNT" -gt 0 ]; then
  echo "    $IAM_USER already has $KEY_COUNT access key(s); leaving them unchanged."
  echo "    List them with: aws iam list-access-keys --user-name $IAM_USER --profile $AWS_PROFILE"
  ACCESS_KEY_ID="(existing key - check AWS console or IAM list-access-keys)"
  SECRET_ACCESS_KEY="(not shown - existing secrets cannot be retrieved)"
else
  echo "==> Creating first access key for $IAM_USER..."
  read -r ACCESS_KEY_ID SECRET_ACCESS_KEY <<<"$("${AWS[@]}" iam create-access-key \
    --user-name "$IAM_USER" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' \
    --output text)"
fi

WWW_WEBSITE_ENDPOINT="${WWW_DOMAIN}.s3-website-${BUCKET_REGION}.amazonaws.com"
ROOT_WEBSITE_ENDPOINT="${DOMAIN}.s3-website-${BUCKET_REGION}.amazonaws.com"

echo ""
echo "============================================================"
echo "  BOOTSTRAP COMPLETE"
echo "============================================================"
echo ""
echo "--- AWS Credentials ---"
echo "  AWS_ACCESS_KEY_ID:     $ACCESS_KEY_ID"
echo "  AWS_SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"
echo ""
echo "  Add to ~/.aws/credentials:"
echo "    [dummer-deploy]"
echo "    aws_access_key_id = $ACCESS_KEY_ID"
echo "    aws_secret_access_key = $SECRET_ACCESS_KEY"
echo ""
echo "--- S3 Website Endpoints ---"
echo "  Site bucket:     http://${WWW_WEBSITE_ENDPOINT}"
echo "  Redirect bucket: http://${ROOT_WEBSITE_ENDPOINT}"
echo ""
echo "--- Cloudflare DNS Setup ---"
echo "  1. CNAME www -> ${WWW_WEBSITE_ENDPOINT} (Proxy ON)"
echo "  2. CNAME @   -> ${ROOT_WEBSITE_ENDPOINT} (Proxy ON / flattening)"
echo "  3. SSL/TLS mode: Flexible"
echo ""
echo "--- Shared ALB For Dynamic Subdomains ---"
echo "  Point dev/stage/etc at your ALB, not these S3 website endpoints."
echo ""
echo "--- Verification ---"
echo "  curl -I http://${WWW_WEBSITE_ENDPOINT}"
echo "  curl -I http://${ROOT_WEBSITE_ENDPOINT}"
echo "  aws s3 ls s3://${WWW_DOMAIN} --profile dummer-deploy"
echo "============================================================"
