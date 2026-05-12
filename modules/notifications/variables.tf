variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "notification_email" {
  type        = string
  default     = ""
  description = "Optional email address that subscribes to the transactions SNS topic. Leave empty to skip the subscription."
}
