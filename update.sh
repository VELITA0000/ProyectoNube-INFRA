#!/usr/bin/env bash
# INFRA/update.sh — re-apply Terraform after editing .tf files or terraform.tfvars
# (e.g. enabling api_lambda_bundle_file, adding stripe_webhook_secret, infra changes).
#
# Buckets are created/managed by INFRA/create.sh out of band. This script reuses the
# names saved in INFRA/environments/prod/.bucket-names. Run create.sh first.
set -euo pipefail

INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$INFRA_ROOT/environments/prod"
WATERMARK_SRC="$INFRA_ROOT/modules/lambda/src"
TFVARS="$PROD_DIR/terraform.tfvars"
BUCKETS_FILE="$PROD_DIR/.bucket-names"

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: $TFVARS does not exist. Run create.sh first."
  exit 1
fi

if [[ ! -f "$BUCKETS_FILE" ]]; then
  echo "ERROR: $BUCKETS_FILE does not exist. Run create.sh first to provision the S3 buckets."
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials not available. Run 'aws configure' (or set AWS_PROFILE / env vars) and retry."
  exit 1
fi

# shellcheck disable=SC1090
source "$BUCKETS_FILE"
export TF_VAR_originals_bucket_name="$ORIGINALS_BUCKET"
export TF_VAR_frontend_bucket_name="$FRONTEND_BUCKET"

echo "==> Refreshing watermark Lambda dependencies"
cd "$WATERMARK_SRC"
npm install --omit=dev

echo "==> terraform plan"
cd "$PROD_DIR"
terraform plan -input=false

echo "==> terraform apply"
terraform apply -auto-approve -input=false
# `terraform apply` prints its own "Outputs:" block above. We do not
# re-print the "Usefull Outputs:" curated list here; that one lives in
# create.sh because it is only meant for the first apply.
