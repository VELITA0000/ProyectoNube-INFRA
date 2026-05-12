terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Custom attribute. Cognito automatically prefixes this with "custom:" so
  # the API references it as `custom:role` (see API/src/routes/auth.ts).
  # Putting "custom:role" here directly breaks the schema registration with
  # "Type for attribute {custom:role} could not be determined" at signup.
  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 32
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cognito"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.project_name}-${var.environment}-spa"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_group" "photographer" {
  name         = "photographer"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Photographers"
}

resource "aws_cognito_user_group" "client" {
  name         = "client"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Clients"
}
