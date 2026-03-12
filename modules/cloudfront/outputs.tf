# CloudFront Module Outputs
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_id" {
  description = "CloudFront distribution ID — used by CI/CD to create cache invalidations after a frontend deploy"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN — used by the GitHub Actions IAM policy"
  value       = aws_cloudfront_distribution.this.arn
}
