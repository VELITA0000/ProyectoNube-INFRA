variable "project_name" {
  type    = string
  default = "photo-app"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "database_url" {
  type        = string
  sensitive   = true
  description = "Full PostgreSQL connection string (Neon). Provision the database with `npx neonctl@latest init` and paste the URL here, e.g. postgresql://user:pass@ep-xxx.aws.neon.tech/neondb?sslmode=require."
  validation {
    condition     = can(regex("^postgres(ql)?://", var.database_url))
    error_message = "database_url must start with postgres:// or postgresql://."
  }
}

variable "allowed_origins" {
  type        = list(string)
  default     = []
  description = "Extra CORS origins for the originals bucket (in addition to CloudFront)."
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "PriceClass_100 | PriceClass_200 | PriceClass_All"
}

variable "frontend_origin" {
  type        = string
  default     = ""
  description = "Extra CORS origin for originals S3 (e.g. http://localhost:5173). Empty = SPA CloudFront only."
}

variable "existing_iam_role_name" {
  type        = string
  default     = "LabRole"
  description = "IAM role name for Lambda execution (e.g. LabRole); used to build lambda_execution_role_arn output."
}

variable "existing_lambda_role_arn" {
  type        = string
  default     = ""
  description = "If non-empty, overrides the ARN built from existing_iam_role_name."
}

variable "api_lambda_bundle_file" {
  type        = string
  default     = ""
  description = "Path relative to environments/prod to bundle index.js (e.g. ../../../API/.lambda-build/index.js). Empty = placeholder Lambda (no API/ clone or build required)."
  validation {
    condition = (
      trimspace(var.api_lambda_bundle_file) == "" ||
      fileexists(abspath("${path.root}/${trimspace(var.api_lambda_bundle_file)}"))
    )
    error_message = "If api_lambda_bundle_file is set, the file must exist (run npm run bundle:lambda in API/). Leave empty for infra-only with placeholder."
  }
}

variable "stripe_secret_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Optional; checkout returns 503 if empty without Stripe."
}

variable "stripe_webhook_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Optional; whsec_… for /webhooks/stripe."
}

variable "default_photo_unit_price_usd" {
  type        = number
  default     = 12
  description = "Price per photo in USD (DEFAULT_PHOTO_UNIT_PRICE_USD)."
}

variable "originals_bucket_name" {
  type        = string
  description = "Name of the S3 bucket that stores image originals. Created out of band by INFRA/create.sh; passed back into Terraform via TF_VAR_originals_bucket_name."
}

variable "frontend_bucket_name" {
  type        = string
  description = "Name of the S3 bucket that hosts the SPA build. Created out of band by INFRA/create.sh; passed back into Terraform via TF_VAR_frontend_bucket_name."
}

variable "notification_email" {
  type        = string
  default     = ""
  description = "Optional email subscribed to the transactions SNS topic and to CloudWatch alarms. Subscription stays pending until the recipient confirms it."
}
