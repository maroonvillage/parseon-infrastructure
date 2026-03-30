# ECS Service Module Variables
variable "name_prefix" { type = string }

variable "cluster_id" { type = string }
variable "cluster_name" { type = string }

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
# public_subnet_ids kept for potential future use (e.g. public tasks)
variable "public_subnet_ids" {
  type    = list(string)
  default = []
}

variable "ecs_task_role_arn" { type = string }
variable "ecs_execution_role_arn" { type = string }

variable "container_image" { type = string }
variable "container_port" { type = number }

variable "cpu" { type = number }
variable "memory" { type = number }

variable "desired_count" { type = number }

variable "security_group_id" { type = string }

variable "health_check_path" {
  type    = string
  default = "/health"
}
variable "target_group_arn" { type = string }

variable "environment_variables" {
  description = "Environment variables to pass to the container"
  type        = list(object({ name = string, value = string }))
  default     = []
}
