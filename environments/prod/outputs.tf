output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_client_id" {
  value = module.auth.client_id
}

output "cognito_issuer_url" {
  value = module.auth.issuer_url
}

output "cognito_endpoint_url" {
  value       = module.auth.endpoint_url
  description = "Regional Cognito IDP endpoint (informational; the API SDK derives it from AWS_REGION)."
}

output "s3_bucket_originals" {
  value = module.storage.originals_bucket_name
}

output "s3_bucket_originals_arn" {
  value = module.storage.originals_bucket_arn
}

output "sqs_watermark_queue_url" {
  value = module.messages.queue_url
}

output "sqs_watermark_queue_arn" {
  value = module.messages.queue_arn
}

output "database_url" {
  # Echoes the Neon connection string the operator wrote in terraform.tfvars.
  # var.database_url is sensitive, so nonsensitive() unwraps it for the output
  # ONLY (the underlying variable stays sensitive in plan / state / CLI).
  value       = nonsensitive(var.database_url)
  description = "postgresql://… for API/.env or Lambda env (printed in clear text — do not commit)"
}

output "lambda_execution_role_arn" {
  value       = local.lambda_execution_role_arn
  description = "LabRole (or override) for Lambdas created outside Terraform"
}

output "cloudfront_domain_name" {
  value       = module.frontend_cdn.cloudfront_domain_name
  description = "SPA xxx.cloudfront.net domain name"
}

output "cloudfront_origin_url" {
  value       = module.frontend_cdn.cloudfront_origin_url
  description = "SPA HTTPS URL (typical FRONTEND_ORIGIN)"
}

output "s3_frontend_bucket" {
  value       = module.frontend_cdn.s3_bucket_id
  description = "S3 bucket for APP/ static build"
}

output "cloudfront_distribution_id" {
  value       = module.frontend_cdn.cloudfront_distribution_id
  description = "Distribution ID for CloudFront invalidation"
}

output "http_api_endpoint" {
  value       = module.api_http.http_api_endpoint
  description = "Base URL of HTTP API Gateway ($default stage)"
}

output "stripe_webhook_url" {
  value       = "${module.api_http.http_api_endpoint}/webhooks/stripe"
  description = "URL to configure Stripe webhook (after real API is deployed)"
}

output "api_lambda_function_name" {
  value       = module.api_http.lambda_function_name
  description = "API Lambda function name"
}

output "watermark_lambda_function_name" {
  value       = module.watermark_lambda.function_name
  description = "Watermark / image pipeline Lambda (SQS consumer)"
}

output "watermark_lambda_function_arn" {
  value       = module.watermark_lambda.function_arn
  description = "ARN of watermark Lambda"
}

output "sns_transactions_topic_arn" {
  value       = module.notifications.transactions_topic_arn
  description = "SNS topic that receives transactional notifications (set as SNS_TRANSACTIONS_TOPIC_ARN in API)."
}

output "sqs_watermark_dlq_url" {
  value       = module.messages.dlq_url
  description = "Dead-letter queue URL for failed watermark messages."
}

output "sqs_watermark_dlq_arn" {
  value = module.messages.dlq_arn
}

output "cloudwatch_dashboard_name" {
  value       = module.observability.dashboard_name
  description = "CloudWatch dashboard name with API/Lambda/SQS metrics."
}
