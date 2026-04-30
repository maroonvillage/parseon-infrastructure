# ECS Service Module Outputs

# Output the name of the created ECS Service
output "service_name" {
  value = aws_ecs_service.this.name
}
# Output the ARN of the created ECS Service
output "service_arn" {
  value = aws_ecs_service.this.id
}
