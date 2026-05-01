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
  default     = "prod"
}

# ── Networking ─────────────────────────────────────────────────────────────────
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.11.0/24", "10.1.12.0/24"]
}

# ── Compute ────────────────────────────────────────────────────────────────────
variable "ecr_image_tag" {
  description = "Image tag to deploy (e.g. v1.2.3, git-sha). Avoid 'latest' in prod."
  type        = string
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "ecs_cpu" {
  type    = number
  default = 1024
}

variable "ecs_memory" {
  type    = number
  default = 2048
}

variable "ecs_desired_count" {
  type    = number
  default = 2
}

# ── Database ───────────────────────────────────────────────────────────────────
variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

# ── IAM ────────────────────────────────────────────────────────────────────────
variable "secrets_arns" {
  type    = list(string)
  default = []
}

variable "enable_rds_iam_auth" {
  type    = bool
  default = false
}

# ── TLS / CDN ──────────────────────────────────────────────────────────────────
variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for the ALB HTTPS listener."
  type        = string
  default     = null
}

variable "cloudfront_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for CloudFront."
  type        = string
  default     = null
}

# ── GitHub Actions OIDC ─────────────────────────────────────────────────────
variable "github_repository" {
  description = "GitHub repository for the backend in 'owner/repo' format"
  type        = string
}

variable "frontend_github_repository" {
  description = "GitHub repository for the frontend project in 'owner/repo' format — scopes the frontend OIDC role trust policy"
  type        = string
}

# ── Application Secrets ────────────────────────────────────────────────────────
variable "jwt_secret_key" {
  description = "Stable secret key used to sign and verify JWT tokens. Must be the same across all ECS tasks."
  type        = string
  sensitive   = true
}

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

# ── Secrets Manager ─────────────────────────────────────────────────────────────
variable "secrets_recovery_window_in_days" {
  description = "Recovery window for Secrets Manager secrets before permanent deletion."
  type        = number
  default     = null
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
