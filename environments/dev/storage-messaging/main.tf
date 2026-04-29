provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "test-bucket-${data.aws_caller_identity.current.account_id}"
}

# --- S3 ---
resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = true
}

# --- SQS ---
resource "aws_sqs_queue" "this" {
  name = "storage-test-queue"
}

# --- SQS Policy to allow S3 ---
resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.this.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.this.arn
          }
        }
      }
    ]
  })
}

# --- S3 Event Notification ---
resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  queue {
    queue_arn = aws_sqs_queue.this.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.this]
}
