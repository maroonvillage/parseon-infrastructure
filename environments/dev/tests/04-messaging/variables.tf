variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "parseon"
}

variable "environment" {
  type    = string
  default = "dev-messaging-test"
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}

variable "max_receive_count" {
  type    = number
  default = 5
}
