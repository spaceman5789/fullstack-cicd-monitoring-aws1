output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_instance_id" {
  value = aws_db_instance.main.identifier
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}
