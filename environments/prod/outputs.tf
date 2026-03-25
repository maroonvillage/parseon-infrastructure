# Prod environment outputs

output "ecr_repository_url" {
  description = "ECR repository URL — use as the base for container_image"
  value       = module.ecr.repository_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = module.cloudfront.cloudfront_domain_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = module.rds.db_endpoint
}

output "s3_bucket_id" {
  description = "S3 bucket name"
  value       = module.s3.bucket_id
}

output "frontend_bucket_id" {
  description = "Frontend S3 bucket name — sync React build artifacts here: aws s3 sync build/ s3://<bucket> --delete"
  value       = module.s3_frontend.bucket_id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — use for cache invalidations after a frontend deploy"
  value       = module.cloudfront.distribution_id
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = module.sqs.queue_url
}

output "backend_actions_role_arn" {
  description = "IAM role ARN for backend CI/CD — set as GH Actions variable PARSEON_PROD_ACTIONS_ROLE_ARN in parseon-agentic-backend"
  value       = module.github_oidc.role_arn
}

output "frontend_actions_role_arn" {
  description = "IAM role ARN for the frontend CI/CD pipeline — set as GH Actions variable PARSEON_PROD_FRONTEND_ROLE_ARN in the parseon-web-ui repo"
  value       = module.github_oidc_frontend.role_arn
}
