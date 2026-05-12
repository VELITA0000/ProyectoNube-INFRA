output "originals_bucket_id" {
  value = data.aws_s3_bucket.originals.id
}

output "originals_bucket_name" {
  value = data.aws_s3_bucket.originals.id
}

output "originals_bucket_arn" {
  value = data.aws_s3_bucket.originals.arn
}

output "originals_bucket_region" {
  value = data.aws_s3_bucket.originals.region
}
