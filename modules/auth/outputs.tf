data "aws_region" "current" {}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}

output "client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "issuer_url" {
  value = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

# Regional Cognito IDP endpoint the AWS SDK targets for AdminCreateUser /
# AdminInitiateAuth / …. Identical for every user pool in the region; the
# pool itself is selected via the UserPoolId argument on each call. Exposed
# as a Terraform output for operators / debugging — the API no longer needs
# it as an env var because the SDK derives it from AWS_REGION.
output "endpoint_url" {
  value = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com"
}
