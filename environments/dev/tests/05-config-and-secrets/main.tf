provider "aws" {
  region = var.aws_region
}

module "ssm" {
  source = "../../../../modules/ssm"

  environment = var.environment
  parameters = {
    "postgres/host" = "example.internal"
    "postgres/port" = "5432"
    "postgres/db"   = "appdb"
    "postgres/user" = "appuser"
    "s3/bucket"     = "example-bucket"
    "sqs/url"       = "https://sqs.${var.aws_region}.amazonaws.com/123456789012/example"
    "aws/region"    = var.aws_region
  }
}

# ---------------------------------------------------------------------------
# Secrets Manager — sensitive values (passwords, API keys)
# ---------------------------------------------------------------------------
module "secrets" {
  source      = "../../../../modules/secrets"
  environment = var.environment
  db_password = var.db_password
  is_prod     = var.is_prod
}
