project_name    = "fullstack-deploy"
environment     = "staging"
aws_region      = "eu-north-1"

# Compute
app_instance_type        = "t3.micro"
app_desired_count        = 1
app_min_count            = 1
app_max_count            = 2
monitoring_instance_type = "t3.micro"

# Database
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20

# Alerting
alert_email = "alerts-staging@example.com"
