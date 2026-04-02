terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-1-linux"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-2-windows"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ----------------------------
# Security Groups
# ----------------------------

resource "aws_security_group" "linux" {
  name        = "${var.project_name}-linux-sg"
  description = "Linux control node"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-linux-sg"
  }
}

resource "aws_security_group" "windows" {
  name        = "${var.project_name}-windows-sg"
  description = "Windows target node"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-windows-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "linux_ssh_from_my_ip" {
  security_group_id = aws_security_group.linux.id
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"

  description = "SSH from my IP"
}

resource "aws_vpc_security_group_ingress_rule" "windows_rdp_from_my_ip" {
  security_group_id = aws_security_group.windows.id
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"

  description = "RDP from my IP"
}

resource "aws_vpc_security_group_ingress_rule" "windows_winrm_from_linux" {
  security_group_id            = aws_security_group.windows.id
  referenced_security_group_id = aws_security_group.linux.id
  from_port                    = 5986
  to_port                      = 5986
  ip_protocol                  = "tcp"

  description = "WinRM HTTPS from Linux control node"
}

# ----------------------------
# EC2
# ----------------------------

locals {
  windows_user_data = templatefile("${path.module}/templates/windows-user-data.ps1.tftpl", {})

  linux_user_data = templatefile("${path.module}/templates/linux-user-data.sh.tftpl", {
    windows_private_ip    = aws_instance.windows.private_ip
    rdp_allowed_remote_ip = var.my_ip_cidr
  })
}

resource "aws_instance" "windows" {
  ami                         = data.aws_ssm_parameter.windows_ami.value
  instance_type               = var.windows_instance_type
  subnet_id                   = aws_subnet.public_2.id
  vpc_security_group_ids      = [aws_security_group.windows.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  get_password_data           = true

  user_data                   = local.windows_user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-windows"
    OS   = "Windows Server 2022"
  }
}

resource "aws_instance" "amazon_linux" {
  ami                         = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type               = var.linux_instance_type
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.linux.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data                   = local.linux_user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-amazon-linux"
    OS   = "Amazon Linux 2023"
    Role = "Ansible Control Node"
  }
}
  depends_on = [aws_instance.windows]
}
