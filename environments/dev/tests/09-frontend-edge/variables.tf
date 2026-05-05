variable "aws_region" {
  description = "AWS region for test resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for test resource names."
  type        = string
  default     = "parseon"
}

variable "environment" {
  description = "Environment/test slice name. Keep this unique to avoid bucket/name collisions."
  type        = string
  default     = "dev-frontend-edge"
}

variable "vpc_cidr" {
  description = "CIDR block for the frontend-edge test VPC."
  type        = string
  default     = "10.90.0.0/16"
}

variable "availability_zones" {
  description = "Availability Zones used by the test VPC."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the ALB."
  type        = list(string)
  default     = ["10.90.1.0/24", "10.90.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs. Included because the VPC module expects them."
  type        = list(string)
  default     = ["10.90.101.0/24", "10.90.102.0/24"]
}

variable "allowed_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "api_port" {
  description = "API target port used by the ALB target group."
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "ALB target group health check path."
  type        = string
  default     = "/health"
}

variable "alb_certificate_arn" {
  description = "Optional ACM certificate ARN for the ALB HTTPS listener. Usually null for dev tests."
  type        = string
  default     = null
}

variable "cloudfront_acm_certificate_arn" {
  description = "Optional ACM certificate ARN for CloudFront. Must be in us-east-1 if provided. Usually null for dev tests."
  type        = string
  default     = null
}

variable "index_html_content" {
  description = "HTML content uploaded to the frontend S3 bucket for the CloudFront default behavior test."
  type        = string
  default     = "<!doctype html><html><head><title>Frontend Edge Test</title></head><body><h1>frontend-edge-ok</h1></body></html>"
}
