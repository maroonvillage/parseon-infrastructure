output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "queue_url" {
  value = aws_sqs_queue.this.id
}
