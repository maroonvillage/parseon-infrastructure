# ECR Module Outputs

output "repository_url" {
  description = "Full ECR repository URL (use as container_image in ecs_service)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.this.arn
}
