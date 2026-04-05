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

module "s3_frontend" {
  source      = "../../modules/s3_frontend"
  name_prefix = "${var.project_name}-${var.environment}"
}

module "sqs" {
  source      = "../../modules/sqs"
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# IAM (application roles — ECS task + execution)
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# SSM Parameter Store — non-sensitive config
# ---------------------------------------------------------------------------
module "ssm" {
  source      = "../../modules/ssm"
  environment = var.environment

  parameters = {
    "postgres/host"  = split(":", module.rds.db_endpoint)[0]
    "postgres/port"  = tostring(module.rds.db_port)
    "postgres/db"    = module.rds.db_name
    "postgres/user"  = var.db_username
    "s3/bucket_name" = module.s3.bucket_id
    "sqs/queue_url"  = module.sqs.queue_url
    "aws/region"     = var.aws_region
  }
}

module "iam" {
  source = "../../modules/iam"

  name_prefix         = "${var.project_name}-${var.environment}"
  s3_bucket_arns      = [module.s3.bucket_arn]
  sqs_queue_arns      = [module.sqs.queue_arn]
  enable_rds_iam_auth = var.enable_rds_iam_auth

  # Execution role needs these to inject values via the container `secrets:` block
  secrets_arns       = [aws_secretsmanager_secret.db_password.arn]
  ssm_parameter_arns = values(module.ssm.parameter_arns)
}

# ---------------------------------------------------------------------------
# Secrets Manager — sensitive values (passwords, API keys)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "parseon/${var.environment}/db_password"
  recovery_window_in_days = 0 # dev: allow immediate deletion without waiting period
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
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
  skip_final_snapshot   = true
  deletion_protection   = false
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

  # Plain-text env vars (non-sensitive, not secret-injected)
  environment_variables = [
    { name = "STORAGE_TYPE", value = "s3" },
    { name = "AWS_REGION", value = var.aws_region },
  ]

  # Secrets and config pulled from SSM/Secrets Manager at task launch.
  # ECS injects these as environment variables — the container never handles the ARNs.
  secret_variables = [
    { name = "POSTGRES_HOST", valueFrom = module.ssm.parameter_arns["postgres/host"] },
    { name = "POSTGRES_PORT", valueFrom = module.ssm.parameter_arns["postgres/port"] },
    { name = "POSTGRES_DB", valueFrom = module.ssm.parameter_arns["postgres/db"] },
    { name = "POSTGRES_USER", valueFrom = module.ssm.parameter_arns["postgres/user"] },
    { name = "POSTGRES_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
    { name = "S3_BUCKET_NAME", valueFrom = module.ssm.parameter_arns["s3/bucket_name"] },
    { name = "SQS_QUEUE_URL", valueFrom = module.ssm.parameter_arns["sqs/queue_url"] },
  ]

  # The ECS service requires the target group to be attached to an ALB listener
  # before it can register tasks. This explicit dependency ensures all ALB
  # resources (including listeners) are fully created first.
  depends_on = [module.alb]
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name_prefix         = "${var.project_name}-${var.environment}"
  alb_dns_name        = module.alb.alb_dns_name
  acm_certificate_arn = var.cloudfront_certificate_arn

  s3_frontend_bucket_id                   = module.s3_frontend.bucket_id
  s3_frontend_bucket_arn                  = module.s3_frontend.bucket_arn
  s3_frontend_bucket_regional_domain_name = module.s3_frontend.bucket_regional_domain_name
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC
# ---------------------------------------------------------------------------
module "github_oidc" {
  source = "../../modules/github_oidc"

  name_prefix          = "${var.project_name}-${var.environment}"
  github_repository    = var.github_repository
  ecr_repository_arns  = [module.ecr.repository_arn]
  create_oidc_provider = var.create_github_oidc_provider

  frontend_bucket_arn         = module.s3_frontend.bucket_arn
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}

# Dedicated least-privilege role for the frontend CI/CD pipeline.
# Only has S3 sync + CloudFront invalidation — no ECR or ECS access.
module "github_oidc_frontend" {
  source = "../../modules/github_oidc"

  name_prefix                = "${var.project_name}-${var.environment}-frontend"
  github_repository          = var.frontend_github_repository
  create_oidc_provider       = false # Provider already created by github_oidc module above
  lookup_oidc_provider       = false # ARN is passed directly — avoids data-source lookup at plan time
  existing_oidc_provider_arn = module.github_oidc.oidc_provider_arn

  frontend_bucket_arn         = module.s3_frontend.bucket_arn
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}
