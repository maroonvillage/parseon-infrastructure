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
# ── Security ─────────────────────────────────────────────────────────────────
variable "enable_production_hardening" {
  description = "Enables production-grade hardening controls. Usually true only in prod."
  type        = bool
  default     = false
}

variable "rds_multi_az" {
  description = "Whether RDS should run in Multi-AZ mode."
  type        = bool
  default     = null
}

variable "rds_deletion_protection" {
  description = "Whether RDS deletion protection should be enabled."
  type        = bool
  default     = null
}

variable "rds_skip_final_snapshot" {
  description = "Whether to skip the final DB snapshot on deletion."
  type        = bool
  default     = null
}

variable "rds_backup_retention_period" {
  description = "Number of days to retain RDS automated backups."
  type        = number
  default     = null
}

variable "rds_final_snapshot_identifier_prefix" {
  description = "Prefix used for final RDS snapshot identifiers."
  type        = string
  default     = "final"
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
variable "ecr_image_tag" {
  description = "Image tag to deploy. Prefer immutable Git SHA tags over latest."
  type        = string
  default     = "latest"
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

# ── GitHub Actions OIDC ────────────────────────────────────────────────────────
variable "github_repository" {
  description = "GitHub repository in 'owner/repo' format — used to scope the OIDC trust policy"
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Set to false if the GitHub Actions OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}

variable "frontend_github_repository" {
  description = "GitHub repository for the frontend project in 'owner/repo' format — scopes the frontend OIDC role trust policy"
  type        = string
}

# ── TLS / CDN ──────────────────────────────────────────────────────────────────
variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for the ALB HTTPS listener. Leave null until a certificate exists."
  type        = string
  default     = null
}

variable "cloudfront_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for CloudFront. Leave null to use the default CloudFront certificate."
  type        = string
  default     = null
}

variable "backend_github_oidc_subjects" {
  description = "Allowed GitHub OIDC subjects for backend CI/CD."
  type        = list(string)
  default     = []
}

variable "frontend_github_oidc_subjects" {
  description = "Allowed GitHub OIDC subjects for frontend CI/CD."
  type        = list(string)
  default     = []
}
# ── Logging ───────────────────────────────────────────────────────────────────
variable "ecs_log_retention_in_days" {
  description = "CloudWatch log retention period for ECS container logs."
  type        = number
  default     = 30
}


variable "ecs_autoscaling_min_capacity" {
  description = "Minimum ECS service task count for autoscaling."
  type        = number
  default     = 1
}

variable "ecs_autoscaling_max_capacity" {
  description = "Maximum ECS service task count for autoscaling."
  type        = number
  default     = 4
}

variable "ecs_autoscaling_cpu_target" {
  description = "Target ECS average CPU utilization percentage."
  type        = number
  default     = 60
}



variable "cloudfront_alb_origin_protocol_policy" {
  description = "Protocol policy CloudFront uses when connecting to the ALB origin."
  type        = string
  default     = null
}

variable "enable_waf" {
  description = "Whether to create and attach AWS WAF to CloudFront."
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Whether to enable centralized access logging."
  type        = bool
  default     = false
}

variable "access_logs_bucket_name" {
  description = "Optional existing bucket for access logs."
  type        = string
  default     = null
}

variable "alb_access_logs_prefix" {
  description = "Prefix for ALB access logs."
  type        = string
  default     = "alb"
}

variable "cloudfront_access_logs_prefix" {
  description = "Prefix for CloudFront access logs."
  type        = string
  default     = "cloudfront"
}

# ── VPC Endpoints ─────────────────────────────────────────────────────────────
variable "enable_vpc_endpoints" {
  description = "Whether to create VPC endpoints for private AWS service access."
  type        = bool
  default     = false
}

variable "vpc_endpoint_services" {
  description = "Interface endpoint services to create."
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "sqs"
  ]
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to create an S3 gateway endpoint."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Whether to use one NAT Gateway. Dev usually true. Prod usually false."
  type        = bool
  default     = null
}

variable "enable_customer_managed_kms" {
  description = "Whether to use customer-managed KMS keys instead of AWS-managed encryption."
  type        = bool
  default     = false
}

variable "kms_deletion_window_in_days" {
  description = "KMS key deletion window."
  type        = number
  default     = 30
}
