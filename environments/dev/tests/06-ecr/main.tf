provider "aws" {
  region = var.aws_region
}

module "ecr" {
  source = "../../../../modules/ecr"

  repository_name      = "${var.project_name}-${var.environment}-test-api"
  image_tag_mutability = var.image_tag_mutability
}
