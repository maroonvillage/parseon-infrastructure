provider "aws" {
  region = var.aws_region
}

module "sqs" {
  source = "../../../../modules/sqs"

  name_prefix                = "${var.project_name}-${var.environment}-test"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_receive_count          = var.max_receive_count
}
