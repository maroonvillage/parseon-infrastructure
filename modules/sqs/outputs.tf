# SQS Module Outputs
output "queue_url" {
  value = aws_sqs_queue.this.id
}

output "queue_arn" {
  value = aws_sqs_queue.this.arn
}

output "dlq_arn" {
  value = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}
