output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}

output "api_lambda_log_group" {
  value = aws_cloudwatch_log_group.api_lambda.name
}

output "watermark_lambda_log_group" {
  value = aws_cloudwatch_log_group.watermark_lambda.name
}
