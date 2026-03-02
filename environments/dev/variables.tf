# ── Core ──────────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier — used as a prefix on every resource name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "dev"
}

# ── Networking ─────────────────────────────────────────────────────────────────
variable "availability_zones" {
  description = "List of AZs to use for subnets (must match subnet CIDR counts)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── Compute ────────────────────────────────────────────────────────────────────
variable "container_image" {
  description = "Full ECR image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/app:latest)"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8000
}

variable "ecs_cpu" {
  description = "Fargate CPU units (256 | 512 | 1024 | 2048 | 4096)"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "Fargate memory in MiB"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of running ECS tasks"
  type        = number
  default     = 1
}

# ── Database ───────────────────────────────────────────────────────────────────
variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS instance — pass via TF_VAR_db_password env var, never commit"
  type        = string
  sensitive   = true
}

# ── IAM ────────────────────────────────────────────────────────────────────────
variable "secrets_arns" {
  description = "List of Secrets Manager ARNs the ECS task role is allowed to read"
  type        = list(string)
  default     = []
}

variable "enable_rds_iam_auth" {
  description = "Grant the ECS task role the rds-db:connect permission"
  type        = bool
  default     = false
}

# ── TLS / CDN ──────────────────────────────────────────────────────────────────
variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate (in us-east-1 OR the ALB region) used by the ALB HTTPS listener"
  type        = string
}

variable "cloudfront_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 used by CloudFront"
  type        = string
}
