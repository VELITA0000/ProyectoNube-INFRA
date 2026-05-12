# PROD stack: S3, SQS, Cognito, SPA CloudFront, HTTP API Gateway + API Lambda.
# Lambda may start with placeholder code (no API/ build); real bundle is optional via tfvars.
# The database is NOT managed here — it lives on Neon (https://neon.tech). Provision it once
# with `npx neonctl@latest init`, then paste the connection string into terraform.tfvars
# (`database_url = "postgresql://…?sslmode=require"`).

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Credentials come from the AWS default credential chain (aws configure / env vars / IAM role).
# Do not pass access_key/secret_key/token here; keep credentials out of the repo.
provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  lambda_execution_role_arn = var.existing_lambda_role_arn != "" ? var.existing_lambda_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.existing_iam_role_name}"
  storage_cors_origins      = distinct(concat(var.allowed_origins, [module.frontend_cdn.cloudfront_origin_url], compact([trimspace(var.frontend_origin)])))
  api_lambda_bundle_abs     = trimspace(var.api_lambda_bundle_file) == "" ? "" : abspath("${path.root}/${trimspace(var.api_lambda_bundle_file)}")
  frontend_origin_for_api   = trimspace(var.frontend_origin) != "" ? trimspace(var.frontend_origin) : module.frontend_cdn.cloudfront_origin_url
}

module "frontend_cdn" {
  source = "../../modules/frontend_cdn"

  project_name = var.project_name
  environment  = "prod"
  bucket_name  = var.frontend_bucket_name
  price_class  = var.cloudfront_price_class
}

module "storage" {
  source = "../../modules/storage"

  project_name    = var.project_name
  environment     = "prod"
  bucket_name     = var.originals_bucket_name
  allowed_origins = local.storage_cors_origins
}

module "messages" {
  source = "../../modules/messages"

  project_name       = var.project_name
  environment        = "prod"
  visibility_timeout = 90
  max_receive_count  = 5
}

module "auth" {
  source = "../../modules/auth"

  project_name = var.project_name
  environment  = "prod"
}

module "notifications" {
  source = "../../modules/notifications"

  project_name       = var.project_name
  environment        = "prod"
  notification_email = var.notification_email
}

module "api_http" {
  source = "../../modules/api_http"

  project_name             = var.project_name
  environment              = "prod"
  lambda_bundle_file       = local.api_lambda_bundle_abs
  existing_lambda_role_arn = local.lambda_execution_role_arn
  # Reserved keys (AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
  # AWS_SESSION_TOKEN, …) are NOT set here: Lambda injects them automatically
  # from the execution role and rejects user-provided values. The AWS SDK
  # picks them up from the runtime environment.
  environment_variables = {
    NODE_ENV                     = "production"
    PORT                         = "4000"
    DATABASE_URL                 = var.database_url
    COGNITO_USER_POOL_ID         = module.auth.user_pool_id
    COGNITO_CLIENT_ID            = module.auth.client_id
    S3_BUCKET_ORIGINALS          = module.storage.originals_bucket_name
    SQS_WATERMARK_QUEUE_URL      = module.messages.queue_url
    FRONTEND_ORIGIN              = local.frontend_origin_for_api
    STRIPE_SECRET_KEY            = var.stripe_secret_key
    STRIPE_WEBHOOK_SECRET        = var.stripe_webhook_secret
    SNS_TRANSACTIONS_TOPIC_ARN   = module.notifications.transactions_topic_arn
    DEFAULT_PHOTO_UNIT_PRICE_USD = tostring(var.default_photo_unit_price_usd)
  }
}

# SQS-triggered worker: copies originals → watermarked/ + thumbnails/ and
# updates the photos row in Postgres (Neon) (status = ready, watermarked_url +
# thumbnail_url populated with S3 keys). Source code lives in modules/lambda/src.
# Run `npm install --omit=dev` in INFRA/modules/lambda/src before terraform plan/apply
# so the zip includes the AWS SDK and `pg`.
module "watermark_lambda" {
  source = "../../modules/lambda"

  project_name             = var.project_name
  environment              = "prod"
  s3_bucket_name           = module.storage.originals_bucket_name
  s3_bucket_arn            = module.storage.originals_bucket_arn
  sqs_queue_arn            = module.messages.queue_arn
  existing_lambda_role_arn = local.lambda_execution_role_arn
  database_url             = var.database_url
}

# CloudWatch dashboard, log groups (with retention) and alarms.
# Alarm actions go to the SNS notifications topic when present.
module "observability" {
  source = "../../modules/observability"

  project_name                   = var.project_name
  environment                    = "prod"
  api_lambda_function_name       = module.api_http.lambda_function_name
  watermark_lambda_function_name = module.watermark_lambda.function_name
  watermark_queue_name           = module.messages.queue_name
  watermark_dlq_name             = module.messages.dlq_name
  alarm_topic_arn                = module.notifications.transactions_topic_arn
}
