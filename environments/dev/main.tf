terraform {
  cloud {
    organization = "maroonvillage-hcp-organization"
    workspaces {
      name = "parseon-agentic-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security_groups" {
  source = "../../modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  api_port     = var.container_port
}

# ---------------------------------------------------------------------------
# Storage & Messaging
# ---------------------------------------------------------------------------
module "s3" {
  source      = "../../modules/s3"
  name_prefix = "${var.project_name}-${var.environment}"
}

module "sqs" {
  source      = "../../modules/sqs"
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# IAM (application roles — ECS task + execution)
# ---------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  name_prefix         = "${var.project_name}-${var.environment}"
  s3_bucket_arns      = [module.s3.bucket_arn]
  sqs_queue_arns      = [module.sqs.queue_arn]
  secrets_arns        = var.secrets_arns
  enable_rds_iam_auth = var.enable_rds_iam_auth
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  project_name          = var.project_name
  environment           = var.environment
  private_subnet_ids    = module.vpc.private_subnet_ids
  rds_security_group_id = module.security_groups.rds_sg_id
  db_username           = var.db_username
  db_password           = var.db_password
  multi_az              = false
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  repository_name        = "${var.project_name}-api"
  image_tag_mutability   = "MUTABLE"
  max_image_count        = 10
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------
module "ecs_cluster" {
  source      = "../../modules/ecs_cluster"
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Load Balancing & CDN
# ---------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  name_prefix       = "${var.project_name}-${var.environment}"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  target_port       = var.container_port
  certificate_arn   = var.alb_certificate_arn
}

module "ecs_service" {
  source = "../../modules/ecs_service"

  name_prefix = "${var.project_name}-${var.environment}"

  cluster_id   = module.ecs_cluster.cluster_id
  cluster_name = module.ecs_cluster.cluster_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  ecs_task_role_arn      = module.iam.ecs_task_role_arn
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn

  container_image = "${module.ecr.repository_url}:${var.ecr_image_tag}"
  container_port  = var.container_port

  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.ecs_desired_count

  security_group_id = module.security_groups.ecs_api_sg_id
  target_group_arn  = module.alb.target_group_arn
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name_prefix         = "${var.project_name}-${var.environment}"
  alb_dns_name        = module.alb.alb_dns_name
  acm_certificate_arn = var.cloudfront_certificate_arn
}
