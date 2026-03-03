# CloudFront Module Variables
variable "name_prefix" { type = string }

variable "alb_dns_name" { type = string }

variable "acm_certificate_arn" {
  type = string
}
