# SSM Module Outputs

output "parameter_arns" {
  description = "Map of parameter name → ARN. Pass values into ecs_service secret_variables[*].valueFrom."
  value       = { for k, p in aws_ssm_parameter.params : k => p.arn }
}

output "parameter_names" {
  description = "List of parameter names created by this module"
  value       = [for p in aws_ssm_parameter.params : p.name]
}
