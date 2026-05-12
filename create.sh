#!/usr/bin/env bash
# INFRA/create.sh — first-time provisioning of all AWS resources.
# Run from anywhere; the script resolves its own directory.
#
# This script ALWAYS starts from a clean slate: any leftover terraform.tfstate
# from a previous run is removed before init/apply. Use INFRA/update.sh for
# incremental infra changes that must keep the existing state.
#
# Prerequisites (manual, outside the script):
#   - AWS CLI authenticated (aws configure / SSO / env vars). Credentials are NEVER
#     stored in this repo; Terraform reads them from the AWS default credential chain.
#   - A Neon Postgres database provisioned (`npx neonctl@latest init`); the
#     resulting connection string must be pasted into terraform.tfvars as
#     `database_url = "postgresql://…?sslmode=require"`.
#   - INFRA/environments/prod/terraform.tfvars filled (database_url +
#     stripe_secret_key + stripe_webhook_secret).
#
# Out-of-band buckets:
#   - In AWS Academy / LabRole, s3:GetBucketObjectLockConfiguration is explicitly
#     denied, which crashes the aws_s3_bucket Terraform resource. This script
#     therefore creates the two S3 buckets directly with the AWS CLI BEFORE
#     terraform apply, and exposes their names to Terraform as TF_VAR_*.
#     Terraform references the buckets through `data "aws_s3_bucket"`.
#   - Names are saved in INFRA/environments/prod/.bucket-names so update.sh and
#     destroy.sh use the same buckets.
set -euo pipefail

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$INFRA_ROOT/environments/prod"
WATERMARK_SRC="$INFRA_ROOT/modules/lambda/src"
TFVARS="$PROD_DIR/terraform.tfvars"
BUCKETS_FILE="$PROD_DIR/.bucket-names"
ACCOUNT_FILE="$PROD_DIR/.last-account"

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: $TFVARS does not exist."
  echo "Copy terraform.tfvars.example to terraform.tfvars and fill database_url"
  echo "(get one with 'npx neonctl@latest init') plus the Stripe keys."
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials not available. Run 'aws configure' (or set AWS_PROFILE / env vars) and retry."
  exit 1
fi

PROJECT_NAME="${PROJECT_NAME:-photo-app}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
CURRENT_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"

# Always start from a clean slate.
#
# create.sh is the FIRST-TIME provisioning script. Use update.sh for any
# incremental change. Wiping the leftover Terraform state here protects
# against the most common failure in AWS Academy / Vocareum labs: the lab
# resets every few hours and hands you a brand-new AWS account, but the
# previous state still references resources in the OLD account. Refreshing
# those resources fails with 403 AccessDenied and the plan dies. By dropping
# state at the start, every create.sh run rebuilds the stack from scratch
# against whichever account is currently authenticated.
#
# Files removed:
#   - terraform.tfstate          (current state)
#   - terraform.tfstate.backup   (last backup)
#   - terraform.tfstate.*.backup (older backups)
#   - .terraform.tfstate.lock.info (stale lock from an interrupted run)
#   - tfplan                     (saved plan files, if any)
#
# Files KEPT:
#   - .terraform/                (provider plugin cache; speeds up re-init)
#   - .terraform.lock.hcl        (provider version pin; committed file)
echo "==> Cleaning residual Terraform state from previous runs"
rm -f "$PROD_DIR/terraform.tfstate" \
      "$PROD_DIR/terraform.tfstate.backup" \
      "$PROD_DIR"/terraform.tfstate.*.backup \
      "$PROD_DIR/.terraform.tfstate.lock.info" \
      "$PROD_DIR/tfplan"

# Lab-reset detector for the bucket cache: when the AWS account changes the
# previously cached bucket names belong to the other account and head-bucket
# returns 403, so we cannot reuse them. Drop the cache and let ensure_bucket
# (below) generate fresh names against the current account.
if [[ -f "$ACCOUNT_FILE" ]]; then
  LAST_ACCOUNT="$(cat "$ACCOUNT_FILE")"
  if [[ -n "$LAST_ACCOUNT" && "$LAST_ACCOUNT" != "$CURRENT_ACCOUNT" ]]; then
    echo "==> Lab account changed ($LAST_ACCOUNT -> $CURRENT_ACCOUNT). Dropping cached bucket names."
    rm -f "$BUCKETS_FILE"
  fi
fi

# Reuse bucket names from a previous run if they exist (and we did not just wipe them).
if [[ -f "$BUCKETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BUCKETS_FILE"
fi

account_suffix () { aws sts get-caller-identity --query Account --output text | cut -c1-12; }
fresh_suffix ()   { echo "$(date +%Y%m%d%H%M%S)$(account_suffix)"; }

ORIGINALS_BUCKET="${ORIGINALS_BUCKET:-${PROJECT_NAME}-${ENVIRONMENT}-orig-$(fresh_suffix)}"
FRONTEND_BUCKET="${FRONTEND_BUCKET:-${PROJECT_NAME}-${ENVIRONMENT}-spa-$(fresh_suffix)}"

# Try to create the bucket. Returns 0 on success, 1 if the name is taken
# globally (BucketAlreadyExists) or in S3's deletion-lockout window. Any other
# error aborts the script.
try_create_bucket () {
  local bucket="$1"
  local err

  if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "    s3://$bucket already exists in this account, reusing."
    return 0
  fi

  echo "    Creating s3://$bucket"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    err="$(aws s3api create-bucket --bucket "$bucket" --region "$AWS_REGION" 2>&1 >/dev/null)" && return 0
  else
    err="$(aws s3api create-bucket --bucket "$bucket" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION" 2>&1 >/dev/null)" && return 0
  fi

  if echo "$err" | grep -qE 'BucketAlreadyExists|BucketAlreadyOwnedByYou|OperationAborted'; then
    echo "    Name '$bucket' is globally taken or in S3 deletion lockout."
    return 1
  fi

  echo "ERROR: aws s3api create-bucket failed:"
  echo "$err"
  return 2
}

# Resolve a bucket name: try the cached candidate; if it's taken, regenerate
# a fresh suffix up to N times. Updates the named variable in-place.
ensure_bucket () {
  local var_name="$1"      # ORIGINALS_BUCKET / FRONTEND_BUCKET
  local prefix="$2"        # photo-app-prod-orig / photo-app-prod-spa
  local candidate="${!var_name}"
  local attempt rc

  for attempt in 1 2 3 4 5; do
    set +e
    try_create_bucket "$candidate"
    rc=$?
    set -e

    case "$rc" in
      0)
        printf -v "$var_name" '%s' "$candidate"
        return 0
        ;;
      1)
        candidate="${prefix}-$(fresh_suffix)"
        echo "    Retrying with '$candidate' (attempt $((attempt + 1)))"
        sleep 1
        ;;
      *)
        exit 1
        ;;
    esac
  done

  echo "ERROR: gave up generating a unique bucket name for $var_name after 5 attempts."
  exit 1
}

delete_cloudfront_oac_by_name () {
  local name="$1"

  local id
  id="$(aws cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='${name}'].Id | [0]" \
    --output text 2>/dev/null || true)"

  if [[ -z "${id:-}" || "$id" == "None" || "$id" == "null" ]]; then
    return 0
  fi

  local etag
  etag="$(aws cloudfront get-origin-access-control --id "$id" --query "ETag" --output text 2>/dev/null || true)"
  if [[ -z "${etag:-}" || "$etag" == "None" || "$etag" == "null" ]]; then
    return 0
  fi

  echo "==> Pre-clean: deleting existing CloudFront OAC with same name ($name)"
  aws cloudfront delete-origin-access-control --id "$id" --if-match "$etag" >/dev/null 2>&1 || {
    echo "WARNING: Could not delete OAC '$name' (likely still in use). Terraform may fail with AlreadyExists."
  }
}

delete_cloudfront_response_headers_policy_by_name () {
  local name="$1"

  local id
  id="$(aws cloudfront list-response-headers-policies --type custom \
    --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='${name}'].ResponseHeadersPolicy.Id | [0]" \
    --output text 2>/dev/null || true)"

  if [[ -z "${id:-}" || "$id" == "None" || "$id" == "null" ]]; then
    return 0
  fi

  local etag
  etag="$(aws cloudfront get-response-headers-policy --id "$id" --query "ETag" --output text 2>/dev/null || true)"
  if [[ -z "${etag:-}" || "$etag" == "None" || "$etag" == "null" ]]; then
    return 0
  fi

  echo "==> Pre-clean: deleting existing Response Headers Policy with same name ($name)"
  aws cloudfront delete-response-headers-policy --id "$id" --if-match "$etag" >/dev/null 2>&1 || {
    echo "WARNING: Could not delete response headers policy '$name' (likely still in use). Terraform may fail with AlreadyExists."
  }
}

echo "==> Ensuring S3 buckets exist (out of band, no Terraform)"
ensure_bucket ORIGINALS_BUCKET "${PROJECT_NAME}-${ENVIRONMENT}-orig"
ensure_bucket FRONTEND_BUCKET  "${PROJECT_NAME}-${ENVIRONMENT}-spa"

# Best-effort pre-clean for global CloudFront resources that often remain when the
# terraform state is lost (common in labs). If they are in use, AWS will reject
# deletion and Terraform may still fail with AlreadyExists.
delete_cloudfront_oac_by_name "${PROJECT_NAME}-${ENVIRONMENT}-spa-oac"
delete_cloudfront_response_headers_policy_by_name "${PROJECT_NAME}-${ENVIRONMENT}-spa-headers"

# Persist names so update.sh and destroy.sh can reuse them.
cat > "$BUCKETS_FILE" <<EOF
ORIGINALS_BUCKET="$ORIGINALS_BUCKET"
FRONTEND_BUCKET="$FRONTEND_BUCKET"
EOF

export TF_VAR_originals_bucket_name="$ORIGINALS_BUCKET"
export TF_VAR_frontend_bucket_name="$FRONTEND_BUCKET"

echo "==> Installing watermark Lambda dependencies"
cd "$WATERMARK_SRC"
npm install --omit=dev

echo "==> terraform init"
cd "$PROD_DIR"
terraform init

echo "==> terraform plan"
terraform plan -input=false

echo "==> terraform apply"
terraform apply -auto-approve -input=false

# Remember the AWS account this state belongs to so the next create.sh run
# can detect a lab reset and wipe stale state automatically.
echo "$CURRENT_ACCOUNT" > "$ACCOUNT_FILE"

# Curated copy-paste block printed right after `terraform apply`'s own
# "Outputs:" section. Only includes values that come FROM Terraform — the
# Stripe webhook signing secret (whsec_…) is set on Stripe AFTER you wire
# the webhook to the API URL, so it never appears here.
echo
echo "Usefull Outputs:"
printf "  %-30s = %s\n" "HTTP_API_ENDPOINT"              "$(terraform output -raw http_api_endpoint)"
printf "  %-30s = %s\n" "DATABASE_URL"                   "$(terraform output -raw database_url)"
printf "  %-30s = %s\n" "COGNITO_USER_POOL_ID"           "$(terraform output -raw cognito_user_pool_id)"
printf "  %-30s = %s\n" "COGNITO_CLIENT_ID"              "$(terraform output -raw cognito_client_id)"
printf "  %-30s = %s\n" "COGNITO_ENDPOINT_URL"           "$(terraform output -raw cognito_endpoint_url)"
printf "  %-30s = %s\n" "COGNITO_ISSUER_URL"             "$(terraform output -raw cognito_issuer_url)"
printf "  %-30s = %s\n" "S3_BUCKET_ORIGINALS"            "$(terraform output -raw s3_bucket_originals)"
printf "  %-30s = %s\n" "SQS_WATERMARK_QUEUE_URL"        "$(terraform output -raw sqs_watermark_queue_url)"
printf "  %-30s = %s\n" "CLOUDFRONT_ORIGIN_URL"          "$(terraform output -raw cloudfront_origin_url)"
printf "  %-30s = %s\n" "SNS_TRANSACTIONS_TOPIC_ARN"     "$(terraform output -raw sns_transactions_topic_arn)"
printf "  %-30s = %s\n" "VITE_API_BASE_URL"              "$(terraform output -raw http_api_endpoint)"
printf "  %-30s = %s\n" "S3_FRONTEND_BUCKET"             "$(terraform output -raw s3_frontend_bucket)"
printf "  %-30s = %s\n" "CLOUDFRONT_DISTRIBUTION_ID"     "$(terraform output -raw cloudfront_distribution_id)"
