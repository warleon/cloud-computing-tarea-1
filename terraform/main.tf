terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

// Región AWS donde se crearán los recursos (ej: us-east-1). Cambia si quieres otra región.
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

// URL completa de la imagen Docker en ECR que usará la task de ECS.
// Ejemplo: 123456789012.dkr.ecr.us-east-1.amazonaws.com/api-crud:latest
variable "image_url" {
  type        = string
  description = "URI de la imagen en ECR, p.ej: <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/api-crud:latest"
}

// (Opcional) ARN de un role IAM que ECS usará como Execution Role (para permisos de ECR, logs, etc).
// Si se deja vacío y `create_execution_role=true`, Terraform intentará crear uno nuevo.
variable "execution_role_arn" {
  type        = string
  description = "(Opcional) ARN de un role de ejecución ECS existente. Si se provee, Terraform no intentará crear uno."
  default     = ""
}

// Booleano que controla si Terraform debe crear un IAM Role de ejecución para ECS.
// Poner false si prefieres reutilizar un role existente (p. ej. LabRole).
variable "create_execution_role" {
  type    = bool
  default = false  # Cambiado a false por defecto para evitar el error de permisos
}

// ARN del LabRole proporcionado por el laboratorio. Se usa como Task Role para las tareas ECS.
variable "lab_role_arn" {
  type        = string
  description = "ARN del role LabRole a usar en TaskRole/ServiceRole"
}

data "aws_vpc" "default" {
  default = true
}

# Reemplazado aws_subnet_ids por aws_subnets (más moderno)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-api-sg-${random_id.sg_suffix.hex}"  # Nombre único
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

  tags = {
    Name = "ECS-API-SecurityGroup"
  }
}

resource "aws_ecr_repository" "api_repo" {
  name = "api-crud"
}

resource "random_id" "sg_suffix" {
  byte_length = 4
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/api-crud"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution_role" {
  count = var.create_execution_role ? 1 : 0
  name  = "ecsTaskExecutionRole-custom-${random_id.sg_suffix.hex}"  # Nombre único

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
  count      = var.create_execution_role ? 1 : 0
  role       = aws_iam_role.ecs_task_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "api_cluster" {
  name = "api-cluster-${random_id.sg_suffix.hex}"  # Nombre único
}

resource "aws_ecs_task_definition" "api_task" {
  family                   = "api-crud-task-${random_id.sg_suffix.hex}"  # Nombre único
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.create_execution_role ? aws_iam_role.ecs_task_execution_role[0].arn : (var.execution_role_arn != "" ? var.execution_role_arn : var.lab_role_arn)
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
  name            = "api-crud-service-${random_id.sg_suffix.hex}"  # Nombre único
  cluster         = aws_ecs_cluster.api_cluster.id
  task_definition = aws_ecs_task_definition.api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.execution_attach]
}

resource "aws_security_group" "api_sg" {
  name        = "api-security-group-${random_id.sg_suffix.hex}"  # Nombre único
  description = "Security group for API EC2 instance"
  vpc_id      = data.aws_vpc.default.id

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
  key_name      = "vockey"
  vpc_security_group_ids = [aws_security_group.api_sg.id]
  # Asociar el instance profile existente para que la instancia muestre LabRole en la consola
  iam_instance_profile = "LabInstanceProfile"

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
    Name = "API-PRUEBA-EC2-${random_id.sg_suffix.hex}"  # Nombre único
  }
}
// Instance profile association handled via aws_instance. Removed separate association resource.

output "ecr_repository_url" {
  value = aws_ecr_repository.api_repo.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.api_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.api_service.name
}

output "ec2_instance_public_ip" {
  value = aws_instance.mi_ec2.public_ip
}

output "security_group_id" {
  value = aws_security_group.api_sg.id
}