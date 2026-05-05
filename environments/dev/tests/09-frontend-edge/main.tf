terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Fixture/Foundation: VPC required by ALB ───────────────────────────────────
module "vpc" {
  source = "../../../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── Fixture/Foundation: Security group required by ALB ────────────────────────
module "security_groups" {
  source = "../../../../modules/security_groups"

  project_name                = var.project_name
  environment                 = var.environment
  vpc_id                      = module.vpc.vpc_id
  api_port                    = var.api_port
  allowed_ingress_cidr_blocks = var.allowed_ingress_cidr_blocks
}

# ── Module under test: private frontend bucket ────────────────────────────────
module "s3_frontend" {
  source = "../../../../modules/s3_frontend"

  name_prefix = "${var.project_name}-${var.environment}"
}

# Test fixture object so CloudFront default behavior has something to serve.
resource "aws_s3_object" "index" {
  bucket       = module.s3_frontend.bucket_id
  key          = "index.html"
  content      = var.index_html_content
  content_type = "text/html"

  depends_on = [module.s3_frontend]
}

# ── Module under test / API-origin fixture: ALB ───────────────────────────────
# This ALB intentionally has no ECS targets in this slice. The goal here is to
# verify CloudFront path-based routing has an ALB origin for /api/*, not to test
# backend service health. ECS target health is covered by 08-api-compute.
module "alb" {
  source = "../../../../modules/alb"

  name_prefix       = "${var.project_name}-${var.environment}"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id
  target_port       = var.api_port
  certificate_arn   = var.alb_certificate_arn
  health_check_path = var.health_check_path
}

# ── Module under test: CloudFront with S3 default origin and ALB API origin ───
module "cloudfront" {
  source = "../../../../modules/cloudfront"

  name_prefix                             = "${var.project_name}-${var.environment}"
  alb_dns_name                            = module.alb.alb_dns_name
  acm_certificate_arn                     = var.cloudfront_acm_certificate_arn
  s3_frontend_bucket_id                   = module.s3_frontend.bucket_id
  s3_frontend_bucket_arn                  = module.s3_frontend.bucket_arn
  s3_frontend_bucket_regional_domain_name = module.s3_frontend.bucket_regional_domain_name

  depends_on = [aws_s3_object.index]
}
