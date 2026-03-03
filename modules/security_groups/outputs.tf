# Security Groups Module Outputs
output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "ecs_api_sg_id" {
  value = aws_security_group.ecs_api.id
}

output "ecs_worker_sg_id" {
  value = aws_security_group.ecs_worker.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}
