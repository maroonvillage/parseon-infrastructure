provider "aws" {
  region = var.region
}

# --- VPC ---
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
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
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

# --- SQS ---
resource "aws_sqs_queue" "this" {
  name = "worker-test-queue"
}

# --- IAM Role for ECS Task ---
resource "aws_iam_role" "ecs_task" {
  name = "worker-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sqs_access" {
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = aws_sqs_queue.this.arn
    }]
  })
}

# --- ECS ---
resource "aws_ecs_cluster" "this" {
  name = "worker-cluster"
}

resource "aws_ecs_task_definition" "this" {
  family                   = "worker-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  task_role_arn = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "worker"
      image = var.image

      environment = [
        {
          name  = "QUEUE_URL"
          value = aws_sqs_queue.this.id
        }
      ]
    }
  ])
}

resource "aws_security_group" "ecs" {
  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "this" {
  name            = "worker-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs.id]
  }
}
