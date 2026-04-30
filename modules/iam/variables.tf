# IAM Module Variables
variable "name_prefix" {
  type = string
}

variable "s3_bucket_arns" {
  type = list(string)
}

variable "sqs_queue_arns" {
  type = list(string)
}

variable "secrets_arns" {
  description = "Secrets Manager ARNs the ECS execution role can read at task launch (for secrets: injection)"
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns" {
  description = "SSM Parameter Store ARNs the ECS execution role can read at task launch (for secrets: injection)"
  type        = list(string)
  default     = []
}

variable "enable_rds_iam_auth" {
  type    = bool
  default = false
}
# RDS IAM auth requires the task role to have permissions to call rds-db:connect, and the execution role to have permissions to call secretsmanager:GetSecretValue on the secret containing the database credentials. If enable_rds_iam_auth is true, then the module will add these permissions to the respective roles.
variable "execution_secrets_arns" {
  description = "Secrets Manager ARNs the ECS execution role may read for task startup secret injection."
  type        = list(string)
  default     = []
}
# If your app code directly calls Secrets Manager at runtime, then you should add the relevant ARNs to task_secrets_arns. If you only use secrets for injection at task startup, then you can leave task_secrets_arns empty and just add the relevant ARNs to execution_secrets_arns.
variable "task_secrets_arns" {
  description = "Secrets Manager ARNs the ECS task role may read at runtime. Keep empty unless app code directly calls Secrets Manager."
  type        = list(string)
  default     = []
}
