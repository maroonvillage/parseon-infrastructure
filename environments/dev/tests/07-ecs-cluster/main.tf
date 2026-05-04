provider "aws" {
  region = var.aws_region
}

module "ecs_cluster" {
  source = "../../../../modules/ecs_cluster"

  name_prefix = "${var.project_name}-${var.environment}-test"
}
