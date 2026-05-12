output "queue_id" {
  value = aws_sqs_queue.watermark.id
}

output "queue_arn" {
  value = aws_sqs_queue.watermark.arn
}

output "queue_url" {
  value = aws_sqs_queue.watermark.url
}

output "queue_name" {
  value = aws_sqs_queue.watermark.name
}

output "dlq_arn" {
  value = aws_sqs_queue.watermark_dlq.arn
}

output "dlq_name" {
  value = aws_sqs_queue.watermark_dlq.name
}

output "dlq_url" {
  value = aws_sqs_queue.watermark_dlq.url
}
