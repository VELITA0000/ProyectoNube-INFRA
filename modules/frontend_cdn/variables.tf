variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_name" {
  type        = string
  description = "Name of the existing S3 bucket for the SPA (created out of band by INFRA/create.sh)."
}

variable "price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "PriceClass_100 (US/Europe) lowers cost vs PriceClass_All"
}
