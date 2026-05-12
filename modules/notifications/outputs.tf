output "transactions_topic_arn" {
  value       = aws_sns_topic.transactions.arn
  description = "SNS topic ARN consumed by the API Lambda for transactional notifications."
}

output "transactions_topic_name" {
  value = aws_sns_topic.transactions.name
}
