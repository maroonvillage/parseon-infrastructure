terraform {
  backend "s3" {
    bucket = "parseon-terraform-state"
    key    = "prod/terraform.tfstate"
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
  name_prefix = "app-prod"
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
module "s3" {
  source      = "../../modules/s3"
  name_prefix = "app-prod"
}
