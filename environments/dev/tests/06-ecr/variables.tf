variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev-ecr-test"
}


variable "image_tag_mutability" {
  description = "Tag mutability setting: MUTABLE or IMMUTABLE. IMMUTABLE is recommended for production."
  type        = string
  default     = "MUTABLE"
}

variable "project_name" {
  type    = string
  default = "parseon"
}
