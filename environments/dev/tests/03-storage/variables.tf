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
  default = "dev-networking-test"
}
