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


variable "enable_access_logs" {
  description = "Whether ALB access logs are enabled."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs."
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "S3 prefix for ALB access logs."
  type        = string
  default     = "alb"
}
