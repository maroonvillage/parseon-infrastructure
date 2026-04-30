variable "name_prefix" {
  description = "Prefix applied to all resource names"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in 'owner/repo' format (e.g. 'acme/parseon-agentic-backend')"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ARNs of the ECR repositories GitHub Actions is allowed to push to. Leave empty for roles that do not need container image access (e.g. frontend-only roles)."
  type        = list(string)
  default     = []
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account (only one allowed per account)"
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an already-created GitHub OIDC provider to use when create_oidc_provider=false. Avoids a data-source lookup that fails during fresh deploys."
  type        = string
  default     = null
}

variable "lookup_oidc_provider" {
  description = "When create_oidc_provider=false, set this to false to use existing_oidc_provider_arn directly instead of looking up the provider from AWS. Must be a literal bool (not a computed value) so Terraform can evaluate it at plan time."
  type        = bool
  default     = true
}

variable "frontend_bucket_arn" {
  description = "ARN of the S3 bucket hosting frontend static assets. When set, grants the CI/CD role permission to sync build artifacts."
  type        = string
  default     = null
}
//
variable "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution. When set, grants the CI/CD role permission to create cache invalidations."
  type        = string
  default     = null
}
# The GitHub OIDC provider can be configured with multiple allowed subject claims (e.g. for multiple repos or environments). If empty, the trust policy will allow any sub claim from the configured provider, so use with caution.
variable "github_oidc_subjects" {
  description = "Allowed GitHub OIDC subject claims. Examples: repo:owner/repo:ref:refs/heads/main or repo:owner/repo:environment:dev."
  type        = list(string)
  default     = []
}
# ARNs of ECS services that GitHub Actions may deploy to. Used to scope down the CI/CD role's permissions. If empty, the role will have permission to deploy to any service in the account, so use with caution.
variable "ecs_service_arns" {
  description = "ECS service ARNs this GitHub Actions role may deploy."
  type        = list(string)
  default     = []
}
