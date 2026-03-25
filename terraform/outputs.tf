output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "monitoring_public_ip" {
  description = "Public IP of the monitoring instance (Grafana/Prometheus)"
  value       = module.monitoring.monitoring_public_ip
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${module.monitoring.monitoring_public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${module.monitoring.monitoring_public_ip}:9090"
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = module.sns.topic_arn
}
