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
  description = "Environment variables to pass to the container (plain text, non-sensitive)"
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "secret_variables" {
  description = "Secrets injected at task launch from SSM Parameter Store or Secrets Manager. valueFrom must be the full parameter/secret ARN."
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
}

variable "enable_deployment_circuit_breaker" {
  description = "Enable ECS deployment circuit breaker."
  type        = bool
  default     = true
}

variable "enable_deployment_rollback" {
  description = "Roll back failed ECS deployments automatically."
  type        = bool
  default     = true
}

# Optional: Configure CloudWatch log retention for ECS container logs
variable "log_retention_in_days" {
  description = "CloudWatch log retention period for ECS container logs."
  type        = number
  default     = 30
}

variable "autoscaling_min_capacity" {
  description = "Minimum ECS service task count for autoscaling."
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum ECS service task count for autoscaling."
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "Target ECS average CPU utilization percentage."
  type        = number
  default     = 60
}
