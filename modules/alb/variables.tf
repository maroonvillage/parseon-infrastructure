# ALB Module Variables
variable "name_prefix" { type = string }

variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }

variable "security_group_id" { type = string }

variable "target_port" { type = number }

variable "certificate_arn" {
  description = "ARN of the ACM certificate for the HTTPS listener. If null, only HTTP is configured."
  type        = string
  default     = null
}

variable "health_check_path" {
  type    = string
  default = "/health"
}
