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

# --- Security Group ---
resource "aws_security_group" "ecs" {
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
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

# --- ECS ---
resource "aws_ecs_cluster" "this" {
  name = "compute-test-cluster"
}

resource "aws_ecs_task_definition" "this" {
  family                   = "compute-test-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name  = "app"
      image = var.image
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = "compute-test-service"
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
