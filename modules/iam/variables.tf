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
  type = list(string)
}

variable "enable_rds_iam_auth" {
  type    = bool
  default = false
}
