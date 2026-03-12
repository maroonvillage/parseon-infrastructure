variable "name_prefix" {
  description = "Prefix applied to all resource names"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in 'owner/repo' format (e.g. 'acme/parseon-agentic-backend')"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ARNs of the ECR repositories GitHub Actions is allowed to push to"
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account (only one allowed per account)"
  type        = bool
  default     = true
}

variable "frontend_bucket_arn" {
  description = "ARN of the S3 bucket hosting frontend static assets. When set, grants the CI/CD role permission to sync build artifacts."
  type        = string
  default     = null
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution. When set, grants the CI/CD role permission to create cache invalidations."
  type        = string
  default     = null
}
