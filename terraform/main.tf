terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "image_url" {
  type        = string
  description = "URI de la imagen en ECR, p.ej: <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/api-crud:latest"
}

variable "lab_role_arn" {
  type        = string
  description = "ARN del role LabRole a usar en TaskRole/ServiceRole"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-api-sg"
  description = "Allow HTTP 8000 and ephemeral and SSH (for debug)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_ecr_repository" "api_repo" {
  name = "api-crud"
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/api-crud"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole-custom"

  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "execution_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "api_cluster" {
  name = "api-cluster"
}

resource "aws_ecs_task_definition" "api_task" {
  family                   = "api-crud-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name      = "api-crud"
      image     = var.image_url
      essential = true
      portMappings = [
        { containerPort = 8000, hostPort = 8000, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api_service" {
  name            = "api-crud-service"
  cluster         = aws_ecs_cluster.api_cluster.id
  task_definition = aws_ecs_task_definition.api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.execution_attach]
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api_repo.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.api_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.api_service.name
}
resource "aws_security_group" "api_sg" {
  name        = "api-security-group2"
  description = "Security group for API EC2 instance"

  # Permitir tráfico HTTP en puerto 8000
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir SSH
  ingress {
  from_port   = 22
  to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "API-SecurityGroup"
  }
}

resource "aws_instance" "mi_ec2" {
  ami           = "ami-004544147dc19dc61"
  instance_type = "t2.micro"
  key_name      = "vockey"   # ajusta a tu keypair
  # subnet_id se asigna automáticamente a la subnet por defecto
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y git python3 python3-pip

              # Clonar repo
              cd /home/ec2-user
              git clone https://github.com/warleon/cloud-computing-tarea-1.git
              cd cloud-computing-tarea-1/app

              # Instalar dependencias
              pip3 install -r requirements.txt

              # Levantar API FastAPI con Uvicorn en puerto 8000
              nohup uvicorn main:app --host 0.0.0.0 --port 8000 > app.log 2>&1 &
              EOF

  tags = {
    Name = "API-Python-EC2"
  }
}