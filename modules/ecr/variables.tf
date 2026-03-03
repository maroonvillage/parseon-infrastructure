# ECR Module Variables

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "Tag mutability setting: MUTABLE or IMMUTABLE. IMMUTABLE is recommended for production."
  type        = string
  default     = "MUTABLE"
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain per lifecycle policy"
  type        = number
  default     = 10
}

variable "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role to grant ECR pull permissions. Leave empty to skip the repository policy."
  type        = string
  default     = ""
}
