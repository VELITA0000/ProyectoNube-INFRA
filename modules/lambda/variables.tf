variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "s3_bucket_arn" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "existing_lambda_role_arn" {
  type        = string
  description = "ARN of existing lab role (LabRole). No custom IAM roles are created in Terraform."
}

variable "database_url" {
  type        = string
  sensitive   = true
  description = "PostgreSQL connection string (Neon). The watermark Lambda uses it to mark photos as ready after copying the S3 object."
}
