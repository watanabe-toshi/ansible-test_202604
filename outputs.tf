output "vpc_id" {
  value = aws_vpc.main.id
}

output "linux_public_ip" {
  value = aws_instance.amazon_linux.public_ip
}

output "linux_private_ip" {
  value = aws_instance.amazon_linux.private_ip
}

output "linux_instance_id" {
  value = aws_instance.amazon_linux.id
}

output "windows_public_ip" {
  value = aws_instance.windows.public_ip
}

output "windows_private_ip" {
  value = aws_instance.windows.private_ip
}

output "windows_instance_id" {
  value = aws_instance.windows.id
}

output "windows_admin_user" {
  value = "Administrator"
}
