variable "aws_region" {
  description = "AWS region for the test slice."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for test resource naming."
  type        = string
  default     = "parseon"
}

variable "environment" {
  description = "Environment/test name used for test resource naming."
  type        = string
  default     = "dev-api-compute-test"
}

variable "vpc_cidr" {
  description = "CIDR block for the API compute test VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones used by the API compute test."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for ALB."
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for ECS tasks."
  type        = list(string)
  default     = ["10.50.101.0/24", "10.50.102.0/24"]
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway for dev/test cost control."
  type        = bool
  default     = true
}

variable "container_port" {
  description = "Port exposed by the test container."
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "Database port used only for security group creation."
  type        = number
  default     = 5432
}

variable "health_check_path" {
  description = "ALB target group health check path."
  type        = string
  default     = "/health"
}

variable "alb_certificate_arn" {
  description = "Optional ACM certificate ARN for HTTPS listener testing. Leave null for HTTP-only dev test."
  type        = string
  default     = null
}

variable "ecr_image_uri" {
  description = "Full ECR image URI including tag for the tiny test image. Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/test-api:abc123"
  type        = string
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired ECS service count for the API compute test."
  type        = number
  default     = 1
}

variable "test_db_password" {
  description = "Non-production placeholder secret used to test ECS secret injection."
  type        = string
  default     = "test-password-not-for-production"
  sensitive   = true
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention period for the test service."
  type        = number
  default     = 7
}

variable "autoscaling_min_capacity" {
  description = "Minimum ECS task count for autoscaling in this test."
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum ECS task count for autoscaling in this test."
  type        = number
  default     = 2
}

variable "autoscaling_cpu_target" {
  description = "Target ECS average CPU utilization percentage."
  type        = number
  default     = 60
}
