# ---------------------------------------------------------------------------
# Secrets Manager — sensitive values (passwords, API keys)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_password" {
  name = "parseon/${var.environment}/db_password"
  recovery_window_in_days = (
    var.secrets_recovery_window_in_days != null
    ? var.secrets_recovery_window_in_days
    : var.is_prod ? 30 : 0
  ) # dev: allow immediate deletion without waiting period
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}
