# Dev environment outputs

output "ecr_repository_url" {
  description = "ECR repository URL — use as the base for container_image"
  value       = module.ecr.repository_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name — update your DNS CNAME to point here"
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

output "ecs_service_name" {
  description = "ECS service name — set as GH Actions variable ECS_SERVICE_STAGING"
  value       = module.ecs_service.service_name
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC — set as GH Actions variable GITHUB_ACTIONS_ROLE_ARN"
  value       = module.github_oidc.role_arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = module.rds.db_endpoint
}

output "s3_bucket_id" {
  description = "S3 bucket name"
  value       = module.s3.bucket_id
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = module.sqs.queue_url
}
