output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_1_id" {
  value = aws_subnet.public_1.id
}

output "public_subnet_2_id" {
  value = aws_subnet.public_2.id
}

output "amazon_linux_instance_id" {
  value = aws_instance.amazon_linux.id
}

output "amazon_linux_public_ip" {
  value = aws_instance.amazon_linux.public_ip
}

output "windows_instance_id" {
  value = aws_instance.windows.id
}

output "windows_public_ip" {
  value = aws_instance.windows.public_ip
}

output "windows_admin_user" {
  value = "Administrator"
}