#!/usr/bin/env bash
# INFRA/destroy.sh — tear down the AWS stack provisioned by create.sh / update.sh.
#
# Prerequisites (manual):
#   - AWS CLI authenticated (aws configure / SSO / env vars). Credentials are NEVER
#     stored in this repo; Terraform reads them from the AWS credential chain.
#
# Safety:
#   - Requires explicit confirmation. Set CONFIRM=yes to skip the prompt
#     (e.g. CI: CONFIRM=yes bash INFRA/destroy.sh).
#
# Order:
#   1. terraform destroy (with -refresh=false to avoid LabRole denies on S3 bucket
#      object-lock reads). Removes CloudFront, API Gateway, Lambdas, Cognito,
#      SQS, SNS, observability, and the sub-resources of the buckets.
#   2. Empty and delete the two S3 buckets that were created out of band by
#      create.sh, using the names cached in .bucket-names.
#
# Note: the database (Neon) is NOT touched by this script. To delete the Neon
# project run `npx neonctl@latest projects delete <project-id>` separately.
set -euo pipefail

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$INFRA_ROOT/environments/prod"
BUCKETS_FILE="$PROD_DIR/.bucket-names"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials not available. Run 'aws configure' (or set AWS_PROFILE / env vars) and retry."
  exit 1
fi

cd "$PROD_DIR"

if [[ ! -d ".terraform" ]]; then
  echo "ERROR: Terraform not initialized in $PROD_DIR. Run 'terraform init' or 'bash INFRA/create.sh' first."
  exit 1
fi

caller="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo unknown)"
echo "==> Stack about to be destroyed (prod):"
echo "    Path: $PROD_DIR"
echo "    Caller: $caller"
echo

if [[ "${CONFIRM:-}" != "yes" ]]; then
  read -r -p "Type 'destroy' to proceed: " answer
  if [[ "$answer" != "destroy" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

ORIG_FROM_STATE=""
SITE_FROM_STATE=""

# Bucket names from the cache file (preferred when present, written by create.sh).
if [[ -f "$BUCKETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BUCKETS_FILE"
fi

# Migrate legacy state: in older versions of this repo the buckets were managed
# as resources (`aws_s3_bucket.*`). They are now read-only data sources, so the
# resource entries must be removed from state to avoid Terraform trying to read /
# destroy them through the LabRole-denied API.
ORIG_FROM_STATE="$(
  terraform state show module.storage.aws_s3_bucket.originals 2>/dev/null \
    | awk -F\" '/^\s*bucket\s+= /{print $2; exit}' || true
)"
SITE_FROM_STATE="$(
  terraform state show module.frontend_cdn.aws_s3_bucket.site 2>/dev/null \
    | awk -F\" '/^\s*bucket\s+= /{print $2; exit}' || true
)"

if [[ -n "$ORIG_FROM_STATE" || -n "$SITE_FROM_STATE" ]]; then
  echo "==> Migrating legacy bucket state (removing aws_s3_bucket.* resources from state)"
  terraform state rm module.storage.aws_s3_bucket.originals 2>/dev/null || true
  terraform state rm module.frontend_cdn.aws_s3_bucket.site 2>/dev/null || true
fi

# Final list of bucket names to clean up out of band.
ORIGINALS_BUCKET="${ORIGINALS_BUCKET:-$ORIG_FROM_STATE}"
FRONTEND_BUCKET="${FRONTEND_BUCKET:-$SITE_FROM_STATE}"

# Provide bucket names to data sources for the destroy plan so they don't fail
# evaluating the configuration. Buckets still exist at this point.
export TF_VAR_originals_bucket_name="${ORIGINALS_BUCKET:-placeholder-not-existing-bucket}"
export TF_VAR_frontend_bucket_name="${FRONTEND_BUCKET:-placeholder-not-existing-bucket}"

echo "==> terraform destroy (refresh disabled to avoid LabRole denies on object-lock reads)"
terraform destroy -auto-approve -input=false -refresh=false || {
  echo "WARNING: terraform destroy reported errors. Continuing with bucket cleanup; review remaining resources in the AWS console afterwards."
}

empty_and_remove_bucket () {
  local bucket="$1"
  if [[ -z "$bucket" || "$bucket" == "null" ]]; then
    return 0
  fi
  if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "    s3://$bucket already gone."
    return 0
  fi

  echo "==> Emptying and deleting s3://$bucket"

  aws s3 rm "s3://$bucket" --recursive >/dev/null 2>&1 || true

  aws s3api list-object-versions --bucket "$bucket" \
      --query 'Versions[].[Key,VersionId]' --output text 2>/dev/null \
    | while IFS=$'\t' read -r key version; do
        [[ -n "${key:-}" && "$version" != "None" ]] || continue
        aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" >/dev/null 2>&1 || true
      done

  aws s3api list-object-versions --bucket "$bucket" \
      --query 'DeleteMarkers[].[Key,VersionId]' --output text 2>/dev/null \
    | while IFS=$'\t' read -r key version; do
        [[ -n "${key:-}" && "$version" != "None" ]] || continue
        aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" >/dev/null 2>&1 || true
      done

  aws s3 rb "s3://$bucket" --force >/dev/null 2>&1 || true
}

delete_cloudfront_oac_by_name () {
  local name="$1"

  # CloudFront is global; ignore region.
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

  echo "==> Deleting CloudFront OAC: $name ($id)"
  aws cloudfront delete-origin-access-control --id "$id" --if-match "$etag" >/dev/null 2>&1 || {
    echo "WARNING: Could not delete OAC '$name'. It may still be in use by a CloudFront distribution."
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

  echo "==> Deleting CloudFront Response Headers Policy: $name ($id)"
  aws cloudfront delete-response-headers-policy --id "$id" --if-match "$etag" >/dev/null 2>&1 || {
    echo "WARNING: Could not delete response headers policy '$name'. It may still be in use by a CloudFront distribution."
  }
}

if [[ -f "$BUCKETS_FILE" ]]; then
  empty_and_remove_bucket "${ORIGINALS_BUCKET:-}"
  empty_and_remove_bucket "${FRONTEND_BUCKET:-}"
  rm -f "$BUCKETS_FILE"
fi

# Drop the lab-account marker so the next create.sh starts fresh.
rm -f "$PROD_DIR/.last-account"

# Best-effort cleanup for global CloudFront resources when state was lost.
# If a distribution still references them, AWS will reject deletion.
delete_cloudfront_oac_by_name "${PROJECT_NAME:-photo-app}-${ENVIRONMENT:-prod}-spa-oac"
delete_cloudfront_response_headers_policy_by_name "${PROJECT_NAME:-photo-app}-${ENVIRONMENT:-prod}-spa-headers"

echo
echo "Done. If any orphan buckets remain (e.g. from older partial applies), list and clean:"
echo "  aws s3 ls | grep '${PROJECT_NAME:-photo-app}-prod-'"
echo "  aws s3 rb s3://BUCKET_NAME --force"
