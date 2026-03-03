# CloudFront Module Variables
variable "name_prefix" { type = string }

variable "alb_dns_name" { type = string }

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate (must be in us-east-1). If null, the default CloudFront certificate is used."
  type        = string
  default     = null
}
