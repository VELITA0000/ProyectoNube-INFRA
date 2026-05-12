variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_name" {
  type        = string
  description = "Name of the existing S3 bucket for originals (created out of band by INFRA/create.sh)."
}

variable "allowed_origins" {
  type        = list(string)
  description = "CORS origins for presigned URL uploads (SPA and API)"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Kept for backwards compatibility; bucket is managed out of band, this value is ignored."
}
