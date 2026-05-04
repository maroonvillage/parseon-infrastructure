variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev-ecr-test"
}

variable "project_name" {
  type    = string
  default = "parseon"
}
