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

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "availability_zones" {
  type = list(string)
  default = [
    "us-east-1a",
    "us-east-1b"
  ]
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = [
    "10.40.1.0/24",
    "10.40.2.0/24"
  ]
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = [
    "10.40.101.0/24",
    "10.40.102.0/24"
  ]
}
