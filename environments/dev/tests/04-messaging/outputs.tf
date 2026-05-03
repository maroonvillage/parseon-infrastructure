output "aws_region" {
  value = var.aws_region
}

output "queue_url" {
  value = module.sqs.queue_url
}

output "queue_arn" {
  value = module.sqs.queue_arn
}

output "dlq_arn" {
  value = module.sqs.dlq_arn
}
