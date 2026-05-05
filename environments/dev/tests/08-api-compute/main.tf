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

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # This test intentionally uses placeholder SSM values so the ECS task definition
  # can exercise execution-role SSM/Secrets injection without requiring RDS/S3/SQS modules.
  test_parameters = {
    "postgres/host"  = "localhost"
    "postgres/port"  = "5432"
    "postgres/db"    = "testdb"
    "postgres/user"  = "testuser"
    "s3/bucket_name" = "test-bucket-placeholder"
    "sqs/queue_url"  = "https://sqs.${var.aws_region}.amazonaws.com/000000000000/test-placeholder"
    "aws/region"     = var.aws_region
  }
}

module "vpc" {
  source = "../../../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
}

module "security_groups" {
  source = "../../../../modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
}

module "alb" {
  source = "../../../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id

  target_port       = var.container_port
  health_check_path = var.health_check_path

  # Keep API-compute test lightweight. Add a certificate only when testing HTTPS.
  certificate_arn = var.alb_certificate_arn
}

module "ecs_cluster" {
  source = "../../../../modules/ecs_cluster"

  name_prefix = local.name_prefix
}

module "ssm" {
  source = "../../../../modules/ssm"

  environment = var.environment
  parameters  = local.test_parameters
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name_prefix}/db_password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.test_db_password
}

module "iam" {
  source = "../../../../modules/iam"

  name_prefix = local.name_prefix

  # Phase 1 hardening shape. If your IAM module still uses `secrets_arns`,
  # replace these two inputs with: secrets_arns = [aws_secretsmanager_secret.db_password.arn]
  execution_secrets_arns = [aws_secretsmanager_secret.db_password.arn]
  task_secrets_arns      = []
  ssm_parameter_arns     = values(module.ssm.parameter_arns)

  # Keep runtime permissions minimal for this slice. This test validates task-role
  # existence/attachment, not S3/SQS behavior. Those are tested in their own slices.
  s3_bucket_arns      = []
  sqs_queue_arns      = []
  enable_rds_iam_auth = false
}

module "ecs_service" {
  source = "../../../../modules/ecs_service"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id

  cluster_id   = module.ecs_cluster.cluster_id
  cluster_name = module.ecs_cluster.cluster_name

  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn

  container_image = var.ecr_image_uri
  container_port  = var.container_port
  cpu             = var.task_cpu
  memory          = var.task_memory
  desired_count   = var.desired_count

  secret_variables = [
    { name = "QUEUE_URL", valueFrom = module.ssm.parameter_arns["sqs/queue_url"] },
  ]

  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security_groups.ecs_api_security_group_id
  target_group_arn   = module.alb.target_group_arn

  log_retention_in_days = var.log_retention_in_days

  enable_deployment_circuit_breaker = true
  enable_deployment_rollback        = true

  autoscaling_min_capacity = var.autoscaling_min_capacity
  autoscaling_max_capacity = var.autoscaling_max_capacity
  autoscaling_cpu_target   = var.autoscaling_cpu_target

  depends_on = [
    module.alb,
    aws_secretsmanager_secret_version.db_password
  ]
}
