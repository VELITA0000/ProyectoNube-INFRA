terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

# In AWS Academy / LabRole, s3:GetBucketObjectLockConfiguration is explicitly
# denied, which crashes the aws_s3_bucket resource. The bucket is therefore
# created out of band by INFRA/create.sh and referenced as a data source here.
data "aws_s3_bucket" "originals" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "originals" {
  bucket = data.aws_s3_bucket.originals.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "originals" {
  bucket = data.aws_s3_bucket.originals.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "originals" {
  bucket = data.aws_s3_bucket.originals.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD", "DELETE"]
    allowed_origins = var.allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_versioning" "originals" {
  bucket = data.aws_s3_bucket.originals.id
  versioning_configuration {
    status = "Enabled"
  }
}
