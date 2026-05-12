terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

data "aws_region" "current" {}

# Log groups for the API Lambda and the watermark worker. AWS Lambda creates
# them lazily on first invocation; defining them here lets us set retention
# explicitly and ensures they show up in CloudWatch Logs from day one.
resource "aws_cloudwatch_log_group" "api_lambda" {
  name              = "/aws/lambda/${var.api_lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-${var.environment}-api-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "watermark_lambda" {
  name              = "/aws/lambda/${var.watermark_lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-${var.environment}-watermark-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Alarms -----------------------------------------------------------------

# API Lambda: surface Errors (any unhandled exception in the handler).
resource "aws_cloudwatch_metric_alarm" "api_lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-api-lambda-errors"
  alarm_description   = "API Lambda is throwing errors."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.api_lambda_function_name
  }

  alarm_actions = compact([var.alarm_topic_arn])
  ok_actions    = compact([var.alarm_topic_arn])
}

# Watermark Lambda: error count.
resource "aws_cloudwatch_metric_alarm" "watermark_lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-watermark-lambda-errors"
  alarm_description   = "Watermark Lambda is throwing errors."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.watermark_lambda_function_name
  }

  alarm_actions = compact([var.alarm_topic_arn])
  ok_actions    = compact([var.alarm_topic_arn])
}

# DLQ: any messages landing here means the watermark worker keeps failing.
resource "aws_cloudwatch_metric_alarm" "watermark_dlq_depth" {
  alarm_name          = "${var.project_name}-${var.environment}-watermark-dlq-depth"
  alarm_description   = "Messages reached the watermark DLQ — investigate."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.watermark_dlq_name
  }

  alarm_actions = compact([var.alarm_topic_arn])
  ok_actions    = compact([var.alarm_topic_arn])
}

# --- Dashboard --------------------------------------------------------------
# Note: RDS-specific metrics (CPU, connections) used to live here. They were
# removed when the database moved off RDS to Neon, which exposes its own
# observability dashboard outside CloudWatch.

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Lambda — invocations / errors / throttles"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.api_lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."],
            [".", "Duration", ".", ".", { "stat" : "Average" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Watermark Lambda — invocations / errors"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.watermark_lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", ".", { "stat" : "Average" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title  = "SQS — queue depth and DLQ"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.watermark_queue_name],
            [".", "ApproximateNumberOfMessagesVisible", "QueueName", var.watermark_dlq_name]
          ]
        }
      }
    ]
  })
}
