# CloudFront Module Variables
variable "name_prefix" { type = string }

variable "alb_dns_name" { type = string }

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate (must be in us-east-1). If null, the default CloudFront certificate is used."
  type        = string
  default     = null
}

variable "s3_frontend_bucket_id" {
  description = "ID (name) of the S3 bucket hosting the React frontend static assets"
  type        = string
}

variable "s3_frontend_bucket_arn" {
  description = "ARN of the S3 bucket hosting the React frontend static assets"
  type        = string
}

variable "s3_frontend_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 frontend bucket (e.g. my-bucket.s3.us-east-1.amazonaws.com)"
  type        = string
}
