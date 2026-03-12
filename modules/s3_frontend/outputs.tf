# S3 Frontend Module Outputs
output "bucket_id" {
  description = "S3 bucket name (ID) for the React frontend"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the frontend S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name for use as a CloudFront S3 origin (e.g. my-bucket.s3.us-east-1.amazonaws.com)"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
