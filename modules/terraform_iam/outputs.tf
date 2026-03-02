# terraform_iam Module Outputs

output "group_name" {
  description = "Name of the IAM group"
  value       = aws_iam_group.terraform_operators.name
}

output "group_arn" {
  description = "ARN of the IAM group"
  value       = aws_iam_group.terraform_operators.arn
}

output "policy_arn" {
  description = "ARN of the Terraform permissions policy"
  value       = aws_iam_policy.terraform_permissions.arn
}

output "user_name" {
  description = "Name of the created IAM user (empty if create_user = false)"
  value       = var.create_user ? aws_iam_user.terraform_operator[0].name : var.existing_user_name
}
