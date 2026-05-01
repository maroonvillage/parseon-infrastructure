variable "name_prefix" {
  description = "Name prefix for WAF resources."
  type        = string
}

variable "scope" {
  description = "WAF scope. Use CLOUDFRONT for CloudFront."
  type        = string
  default     = "CLOUDFRONT"
}
