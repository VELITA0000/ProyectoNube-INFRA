output "http_api_id" {
  value = aws_apigatewayv2_api.http.id
}

output "http_api_endpoint" {
  value       = aws_apigatewayv2_api.http.api_endpoint
  description = "HTTP API base URL (no trailing slash); same host as $default stage"
}

output "lambda_function_name" {
  value = aws_lambda_function.api.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.api.arn
}
