project_name    = "fullstack-deploy"
environment     = "prod"
aws_region      = "eu-north-1"

# Compute
app_instance_type        = "t3.small"
app_desired_count        = 2
app_min_count            = 2
app_max_count            = 4
monitoring_instance_type = "t3.small"

# Database
db_instance_class    = "db.t3.small"
db_allocated_storage = 50

# Alerting
alert_email = "alerts-prod@example.com"
