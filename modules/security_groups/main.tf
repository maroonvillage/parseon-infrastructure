# Security Groups Module
# This module defines the security groups for the ALB, ECS API service, ECS Worker service, and RDS instance.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidr_blocks
  }

  ingress {
    description = "Allow HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidr_blocks
  }

  egress {
    description = "Allow outbound to ECS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}
# Security group for ECS API service
resource "aws_security_group" "ecs_api" {
  name        = "${local.name_prefix}-ecs-api-sg"
  description = "ECS API service SG"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow traffic from ALB"
    from_port       = var.api_port
    to_port         = var.api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (NAT handles routing)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-api-sg"
  }
}
# Security group for ECS Worker service
resource "aws_security_group" "ecs_worker" {
  name        = "${local.name_prefix}-ecs-worker-sg"
  description = "ECS Worker service SG"
  vpc_id      = var.vpc_id

  # No ingress block = no inbound allowed

  egress {
    description = "Allow outbound to internet and RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-worker-sg"
  }
}
# Security group for RDS instance
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS PostgreSQL SG"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow PostgreSQL from ECS API"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.ecs_api.id,
      aws_security_group.ecs_worker.id
    ]
  }

  egress {
    description = "Allow outbound (rarely used)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}
