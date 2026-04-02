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

resource "aws_instance" "windows" {
  ami                         = data.aws_ssm_parameter.windows_ami.value
  instance_type               = var.windows_instance_type
  subnet_id                   = aws_subnet.public_2.id
  vpc_security_group_ids      = [aws_security_group.windows.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  get_password_data           = true

  user_data = <<-EOF
    <powershell>
    $ErrorActionPreference = "Stop"

    Set-Service -Name WinRM -StartupType Automatic
    winrm quickconfig -q

    $cert = New-SelfSignedCertificate `
      -CertStoreLocation Cert:\LocalMachine\My `
      -DnsName $env:COMPUTERNAME

    New-Item `
      -Path WSMan:\localhost\Listener `
      -Address * `
      -Transport HTTPS `
      -CertificateThumbprint $cert.Thumbprint `
      -Force

    New-NetFirewallRule `
      -DisplayName "WinRM HTTPS 5986" `
      -Direction Inbound `
      -Action Allow `
      -Protocol TCP `
      -LocalPort 5986 `
      -Profile Any `
      -ErrorAction SilentlyContinue

    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false

    Restart-Service WinRM
    </powershell>
  EOF

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

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf update -y
    dnf install -y python3 python3-pip git

    sudo -u ec2-user python3 -m pip install --user --upgrade pip
    sudo -u ec2-user python3 -m pip install --user ansible pywinrm

    cat >/etc/profile.d/ansible_path.sh <<'PATH_EOF'
    export PATH=$PATH:/home/ec2-user/.local/bin
    PATH_EOF
    chmod 644 /etc/profile.d/ansible_path.sh

    sudo -u ec2-user mkdir -p /home/ec2-user/ansible

    cat >/home/ec2-user/ansible/ansible.cfg <<'CFG_EOF'
    [defaults]
    inventory = ./inventory.ini
    host_key_checking = False
    interpreter_python = auto_silent
    CFG_EOF

    cat >/home/ec2-user/ansible/inventory.ini <<'INV_EOF'
    [linux]
    localhost ansible_connection=local

    [windows]
    winhost ansible_host=${aws_instance.windows.private_ip}

    [windows:vars]
    ansible_connection=winrm
    ansible_port=5986
    ansible_user=Administrator
    ansible_winrm_transport=ntlm
    ansible_winrm_server_cert_validation=ignore
    # 実行時に ansible_password を渡す
    INV_EOF

    cat >/home/ec2-user/ansible/ping-linux.yml <<'PLAY1_EOF'
    - name: Test Linux
      hosts: linux
      gather_facts: false
      tasks:
        - name: Ping localhost
          ansible.builtin.ping:
    PLAY1_EOF

    cat >/home/ec2-user/ansible/ping-windows.yml <<'PLAY2_EOF'
    - name: Test Windows
      hosts: windows
      gather_facts: false
      tasks:
        - name: Win ping
          ansible.windows.win_ping:
    PLAY2_EOF

    chown -R ec2-user:ec2-user /home/ec2-user/ansible

    sudo -u ec2-user /home/ec2-user/.local/bin/ansible-galaxy collection install ansible.windows
  EOF

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

  depends_on = [aws_instance.windows]
}