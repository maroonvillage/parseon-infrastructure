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
