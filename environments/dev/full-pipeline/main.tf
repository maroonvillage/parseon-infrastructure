terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -----------------------------
# VPC (minimal, 2 public subnets)
# -----------------------------
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.azs[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = var.azs[1]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.rt.id
}

# -----------------------------
# S3 + SQS (pipeline core)
# -----------------------------
resource "aws_s3_bucket" "data" {
  bucket = "${var.project}-pipeline-data-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_sqs_queue" "q" {
  name = "${var.project}-pipeline-queue"
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.q.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.q.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_s3_bucket.data.arn
        }
      }
    }]
  })
}

resource "aws_s3_bucket_notification" "notify" {
  bucket = aws_s3_bucket.data.id

  queue {
    queue_arn = aws_sqs_queue.q.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# ALB
# -----------------------------
resource "aws_lb" "alb" {
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.alb.id]
  load_balancer_type = "application"
}

resource "aws_lb_target_group" "tg" {
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.this.id
  target_type          = "ip"
  deregistration_delay = 10

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -----------------------------
# ECS Cluster
# -----------------------------
resource "aws_ecs_cluster" "cluster" {
  name = "${var.project}-cluster"
}

# -----------------------------
# IAM Role (ECS task)
# -----------------------------
resource "aws_iam_role" "execution" {
  name = "${var.project}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_policy" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${var.project}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "task_policy" {
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------
# API Task
# -----------------------------
resource "aws_ecs_task_definition" "api" {
  family                   = "api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = "api"
    image = var.api_image

    portMappings = [{
      containerPort = 3000
    }]

    environment = [
      { name = "BUCKET_NAME", value = aws_s3_bucket.data.bucket }
    ]
  }])
}

resource "aws_ecs_service" "api" {
  name            = "${var.project}-api-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "api"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.listener]
}

# -----------------------------
# Worker Task
# -----------------------------
resource "aws_ecs_task_definition" "worker" {
  family                   = "worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = "worker"
    image = var.worker_image

    environment = [
      { name = "QUEUE_URL", value = aws_sqs_queue.q.id }
    ]
  }])
}

resource "aws_ecs_service" "worker" {
  name            = "${var.project}-worker-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
}


