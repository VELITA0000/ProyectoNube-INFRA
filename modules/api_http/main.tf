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

locals {
  use_app_bundle = trimspace(var.lambda_bundle_file) != ""
}

data "archive_file" "api_placeholder" {
  count = local.use_app_bundle ? 0 : 1

  type        = "zip"
  output_path = "${path.module}/build/api_lambda_placeholder.zip"
  source {
    content  = <<-EOT
'use strict';
/** Placeholder until you deploy the real bundle (npm run bundle:lambda + apply or update-function-code). */
exports.handler = async () => ({
  statusCode: 503,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  },
  body: JSON.stringify({
    ok: false,
    message: 'Lambda placeholder: deploy code from API/ (see API/README.md and INFRA/README.md).',
  }),
});
EOT
    filename = "index.js"
  }
}

data "archive_file" "api_zip" {
  count = local.use_app_bundle ? 1 : 0

  type        = "zip"
  source_file = var.lambda_bundle_file
  output_path = "${path.module}/build/api_lambda_app.zip"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-${var.environment}-api"
  role          = var.existing_lambda_role_arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 29
  memory_size   = 512

  filename         = local.use_app_bundle ? data.archive_file.api_zip[0].output_path : data.archive_file.api_placeholder[0].output_path
  source_code_hash = local.use_app_bundle ? data.archive_file.api_zip[0].output_base64sha256 : data.archive_file.api_placeholder[0].output_base64sha256

  # No vpc_config: the Lambda no longer needs to reach a private RDS instance.
  # The database is Neon (public TLS endpoint), so the function runs in the
  # default Lambda networking environment with internet access.

  environment {
    variables = var.environment_variables
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-api"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    precondition {
      condition     = !local.use_app_bundle || fileexists(var.lambda_bundle_file)
      error_message = "API bundle missing at the given path. Run npm run bundle:lambda in API/ or leave api_lambda_bundle_file empty to use only the placeholder."
    }
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-${var.environment}-http"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.project_name}-${var.environment}-apigw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  integration_method     = "POST"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}
