terraform {
  backend "s3" {
    bucket = "parseon-terraform-state"
    key    = "dev/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "../modules/vpc"
}

module "security_groups" {
  source = "../modules/security_groups"
}

module "rds" {
  source = "../modules/rds"
}

module "ecs_cluster" {
  source = "../modules/ecs_cluster"
}

module "ecs_service" {
  source = "../modules/ecs_service"
}

module "s3" {
  source = "../modules/s3"
}

module "sqs" {
  source      = "../modules/sqs"
  name_prefix = "app-dev"
}

module "alb" {
  source = "../modules/alb"
}

module "iam" {
  source = "../modules/iam"
}

module "cloudfront" {
  source = "../modules/cloudfront"
}
module "ecs_cluster" {
  source      = "./modules/ecs_cluster"
  name_prefix = "app"
}

module "ecs_service" {
  source = "./modules/ecs_service"

  name_prefix = "app-dev"

  cluster_id   = module.ecs_cluster.cluster_id
  cluster_name = module.ecs_cluster.cluster_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  ecs_task_role_arn      = module.iam.ecs_task_role_arn
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn

  container_image = "your-ecr-repo:latest"
  container_port  = 8080

  cpu           = 512
  memory        = 1024
  desired_count = 1

  security_group_id = module.security_group.ecs_service_sg_id
}

module "s3" {
  source      = "../../modules/s3"
  name_prefix = "app-dev"
}

module "alb" {
  source = "../../modules/alb"

  name_prefix       = "app-dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnets
  security_group_id = module.security_group.alb_sg_id
  target_port       = 8080
  certificate_arn   = var.alb_certificate_arn
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name_prefix         = "app-dev"
  alb_dns_name        = module.alb.alb_dns_name
  acm_certificate_arn = var.cloudfront_certificate_arn
}
