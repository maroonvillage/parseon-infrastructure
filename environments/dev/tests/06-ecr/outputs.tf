output "repository_url" {
  value = module.ecr.repository_url
}

output "repository_arn" {
  value = module.ecr.repository_arn
}
output "aws_region" {
  value = var.aws_region
}

output "repository_name" {
  description = "ECR repository name"
  value       = module.ecr.repository_name
}
