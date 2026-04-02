variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "Linux public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "Windows public subnet CIDR"
  type        = string
  default     = "10.0.2.0/24"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR for AWS SG, example: 203.0.113.10/32"
  type        = string
}

variable "rdp_allowed_remote_ip" {
  description = "Your public IP for Windows Firewall RDP rule, example: 203.0.113.10"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 Key Pair name"
  type        = string
}

variable "linux_instance_type" {
  description = "Amazon Linux instance type"
  type        = string
  default     = "t3.micro"
}

variable "windows_instance_type" {
  description = "Windows instance type"
  type        = string
  default     = "t3.large"
}
