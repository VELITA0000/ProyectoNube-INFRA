terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Requires `npm install` in modules/lambda/src before apply/plan (see README).
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda-watermark.zip"
}

resource "aws_lambda_function" "watermark" {
  function_name = "${var.project_name}-${var.environment}-watermark"
  role          = var.existing_lambda_role_arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  # 90s + 1 GB so jimp can decode a multi-MB JPEG, paint the watermark layer
  # (rotated text bitmap), recompose, and write back without hitting limits.
  timeout     = 90
  memory_size = 1024

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # No vpc_config: Neon is reachable over the public internet on TLS, so the
  # function runs in the default Lambda networking environment.

  environment {
    variables = {
      S3_BUCKET    = var.s3_bucket_name
      DATABASE_URL = var.database_url
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-watermark"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.watermark.arn
  batch_size       = 1
  enabled          = true
}
