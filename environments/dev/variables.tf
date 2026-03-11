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
variable "ecr_image_tag" {
  description = "Image tag to deploy (e.g. latest, v1.2.3, git-sha)"
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
