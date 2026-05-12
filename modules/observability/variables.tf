variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "api_lambda_function_name" {
  type        = string
  description = "Name of the API Lambda (CloudWatch metrics + log group)."
}

variable "watermark_lambda_function_name" {
  type        = string
  description = "Name of the watermark Lambda (CloudWatch metrics + log group)."
}

variable "watermark_queue_name" {
  type        = string
  description = "Name of the watermark SQS queue (for the dashboard)."
}

variable "watermark_dlq_name" {
  type        = string
  description = "Name of the watermark SQS DLQ (alarm + dashboard)."
}

variable "alarm_topic_arn" {
  type        = string
  default     = ""
  description = "Optional SNS topic that receives alarm + OK notifications. Leave empty to skip alarm actions."
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retention in days for the Lambda log groups managed here."
}
