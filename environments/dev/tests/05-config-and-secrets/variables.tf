variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "Master password for the RDS instance — pass via TF_VAR_db_password env var, never commit"
  type        = string
  sensitive   = true
}

variable "secrets_recovery_window_in_days" {
  description = "Recovery window for Secrets Manager secrets before permanent deletion."
  type        = number
  default     = null
}

variable "environment" {
  type    = string
  default = "dev-config-and-secrets-test"
}

variable "is_prod" {
  type    = bool
  default = false
}
