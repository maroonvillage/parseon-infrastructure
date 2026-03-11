output "role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC — set as GH Actions variable PARSEON_DEV_ACTIONS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
