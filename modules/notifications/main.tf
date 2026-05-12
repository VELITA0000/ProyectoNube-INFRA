terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

# Single SNS topic for transactional notifications (purchase succeeded /
# purchase failed / out-of-band alerts). The API Lambda publishes here.
resource "aws_sns_topic" "transactions" {
  name = "${var.project_name}-${var.environment}-transactions"

  tags = {
    Name        = "${var.project_name}-${var.environment}-transactions"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Optional email subscription for ops / admin (set var.notification_email).
# In sandbox accounts the subscription stays "PendingConfirmation" until the
# recipient confirms via the email link.
resource "aws_sns_topic_subscription" "email" {
  count = trimspace(var.notification_email) == "" ? 0 : 1

  topic_arn = aws_sns_topic.transactions.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
