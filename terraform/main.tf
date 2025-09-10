terraform {
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "Su ID de cuenta AWS (se usará para construir el ARN del LabRole)"
  type        = string
  default     = "478701513931"
}

locals {
  lab_role_arn = "arn:aws:iam::${var.account_id}:role/LabRole"
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn = local.lab_role_arn
  }
}

// Repositorio ECR para la imagen del API. Debe hacer docker build & push desde su MV/estación.
resource "aws_ecr_repository" "api" {
  name                 = "crud-api-repo"
  image_tag_mutability = "MUTABLE"
}


# VPC simplificada con 2 subnets públicas
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}
resource "aws_subnet" "public_a" {
vpc_id = aws_vpc.main.id
cidr_block = "10.0.1.0/24"
availability_zone = data.aws_availability_zones.available.names[0]
map_public_ip_on_launch = true
}
resource "aws_subnet" "public_b" {
vpc_id = aws_vpc.main.id
cidr_block = "10.0.2.0/24"
availability_zone = data.aws_availability_zones.available.names[1]
map_public_ip_on_launch = true
}


data "aws_availability_zones" "available" {}


# SGs
resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

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

resource "aws_security_group" "svc" {
  name   = "svc-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 8000
    to_port         = 8000
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


# ECS Cluster
resource "aws_ecs_cluster" "this" { name = "crud-cluster" }


# IAM roles
resource "aws_iam_role" "task_exec" {
name = "crud-task-exec"
assume_role_policy = jsonencode({
Version = "2012-10-17",
Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
})
}
resource "aws_iam_role_policy_attachment" "exec_policy" {
role = aws_iam_role.task_exec.name
policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# ALB
resource "aws_lb" "this" {
name = "crud-alb"
internal = false
load_balancer_type = "application"
security_groups = [aws_security_group.alb.id]
subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}
resource "aws_lb_target_group" "tg" {
  name    = "crud-tg"
  port    = 8000
  protocol = "HTTP"
  vpc_id  = aws_vpc.main.id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Task Definition Fargate
resource "aws_ecs_task_definition" "task" {
  family                   = "crud-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task_exec.arn

  volume {
    name = "data"
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "data"
          containerPath = "/app/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/crud-task"
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}


# ECS Service para ejecutar la task en Fargate y conectarla al ALB
resource "aws_ecs_service" "svc" {
  name            = "crud-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups = [aws_security_group.svc.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "api"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
}


output "alb_dns" {
  description = "DNS name del Application Load Balancer"
  value       = aws_lb.this.dns_name
}
