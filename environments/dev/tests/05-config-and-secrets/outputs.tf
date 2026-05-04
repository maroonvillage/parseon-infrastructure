output "aws_region" {
  value = var.aws_region
}

output "parameter_names" {
  value = module.ssm.parameter_names
}

output "parameter_arns" {
  value = module.ssm.parameter_arns
}

output "secret_arn" {
  value = module.secrets.secret_arn
}
