variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "lambda_bundle_file" {
  type        = string
  default     = ""
  description = "Absolute path to bundle index.js (npm run bundle:lambda in API/). Empty = minimal placeholder zip (apply without building API/)."
}

variable "existing_lambda_role_arn" {
  type = string
}

variable "environment_variables" {
  type        = map(string)
  sensitive   = true
  description = "Lambda environment variables (DATABASE_URL, Stripe, Cognito, etc.)"
}
