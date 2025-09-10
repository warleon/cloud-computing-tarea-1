terraform {}

variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Nombre del par de claves para acceso SSH (debe existir en la región)"
  type        = string
  default     = "vockey"
}

provider "aws" {
  region = var.region
}

# Selecciona una AMI reciente de Amazon Linux 2 (cambia los filtros si prefieres Ubuntu)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Grupo de seguridad: permite SSH (22) y HTTP (80)
resource "aws_security_group" "tarea_web" {
  name        = "tarea_web"
  description = "Permite acceso SSH y HTTP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
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

# Instancia EC2 similar al ejemplo de tu amigo
resource "aws_instance" "tareaTerraformContainer" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.tarea_web.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "InstanciaConTerraform"
  }
}

output "instance_id" {
  description = "ID de la instancia EC2 creada"
  value       = aws_instance.tareaTerraformContainer.id
}

output "public_ip" {
  description = "Dirección IP pública de la instancia"
  value       = aws_instance.tareaTerraformContainer.public_ip
}

output "public_dns" {
  description = "Nombre DNS público de la instancia"
  value       = aws_instance.tareaTerraformContainer.public_dns
}
