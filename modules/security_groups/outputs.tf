# Security Groups Module Outputs
output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "ecs_api_security_group_id" {
  value = aws_security_group.ecs_api.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "ecs_worker_sg_id" {
  value = aws_security_group.ecs_worker.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}
