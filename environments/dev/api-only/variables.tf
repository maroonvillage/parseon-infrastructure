variable "region" {
  default = "us-east-1"
}

variable "image" {}
variable "app_port" {
  default = 3000
}

variable "health_path" {
  default = "/"
}
