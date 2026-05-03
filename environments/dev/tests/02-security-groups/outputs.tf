output "aws_region" {
  value = var.aws_region
}

output "alb_security_group_id" {
  value = module.security_groups.alb_security_group_id
}

output "ecs_api_security_group_id" {
  value = module.security_groups.ecs_api_security_group_id
}

output "rds_security_group_id" {
  value = module.security_groups.rds_security_group_id
}

# output "container_port" {
#   value = var.container_port
# }

# output "db_port" {
#   value = var.db_port
# }
