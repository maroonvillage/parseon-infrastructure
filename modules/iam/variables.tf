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
