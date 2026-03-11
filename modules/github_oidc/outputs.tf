output "role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC — set as GH Actions variable GITHUB_ACTIONS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
