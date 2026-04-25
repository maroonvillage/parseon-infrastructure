variable "region" {
  default = "us-east-1"
}

variable "image" {
  description = "ECR or public image"
}

variable "app_port" {
  default = 3000
}
