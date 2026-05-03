provider "aws" {
  region = var.aws_region
}

module "s3" {
  source      = "../../../../modules/s3"
  name_prefix = "${var.project_name}-${var.environment}"
}

module "s3_frontend" {
  source      = "../../../../modules/s3_frontend"
  name_prefix = "${var.project_name}-${var.environment}"
}
