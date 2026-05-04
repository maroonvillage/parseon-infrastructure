output "secret_arn" {
  description = "ARN of the db_password secret"
  value       = aws_secretsmanager_secret.db_password.arn
}
