# SQS Module
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = "${var.name_prefix}-dlq"
  message_retention_seconds = var.message_retention_seconds

  sqs_managed_sse_enabled = true
}
resource "aws_sqs_queue" "this" {
  name                       = "${var.name_prefix}-queue"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  sqs_managed_sse_enabled = true

  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null
}
/*
Next Improvement Layer (Optional but Recommended Soon)
For SQS:
• Add queue policy to restrict who can send messages
• Add CloudWatch alarms on DLQ depth */
