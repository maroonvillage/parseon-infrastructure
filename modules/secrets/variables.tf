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
  type = string
}

variable "is_prod" {
  type = bool
}
