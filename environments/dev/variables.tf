variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for the ALB"
  type        = string
  default     = "dev"
}


variable "cloudfront_certificate_arn" {
  description = "ARN of the ACM certificate for CloudFront"
  type        = string
  default     = "dev"
}
