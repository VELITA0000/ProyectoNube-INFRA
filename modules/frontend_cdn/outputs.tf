output "s3_bucket_id" {
  value       = data.aws_s3_bucket.site.id
  description = "Bucket name to upload APP build (npm run build)"
}

output "s3_bucket_arn" {
  value = data.aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.site.domain_name
  description = "Host xxx.cloudfront.net"
}

output "cloudfront_origin_url" {
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
  description = "SPA base URL (HTTPS, no trailing slash). Cognito / CORS / VITE"
}
