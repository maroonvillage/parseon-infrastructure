# SSM Parameter Store Module
# Stores non-sensitive configuration values. Secrets (passwords, API keys)
# should go to Secrets Manager instead.

resource "aws_ssm_parameter" "params" {
  for_each = var.parameters

  name  = "/parseon/${var.environment}/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
