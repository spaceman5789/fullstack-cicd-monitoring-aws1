output "monitoring_public_ip" {
  value = aws_instance.monitoring.public_ip
}

output "monitoring_instance_id" {
  value = aws_instance.monitoring.id
}
