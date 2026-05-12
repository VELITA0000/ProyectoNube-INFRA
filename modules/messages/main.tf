terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

resource "aws_sqs_queue" "watermark_dlq" {
  name                      = "${var.project_name}-${var.environment}-watermark-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "${var.project_name}-${var.environment}-watermark-dlq"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sqs_queue" "watermark" {
  name                       = "${var.project_name}-${var.environment}-watermark"
  visibility_timeout_seconds = var.visibility_timeout
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.watermark_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-watermark"
    Environment = var.environment
    Project     = var.project_name
  }
}
