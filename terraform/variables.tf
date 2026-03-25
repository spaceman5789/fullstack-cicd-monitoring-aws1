# ── General ───────────────────────────────────────────────────────
variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "fullstack-deploy"
}

variable "environment" {
  description = "Deployment environment (staging / prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

# ── Networking ───────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ── Compute ──────────────────────────────────────────────────────
variable "app_instance_type" {
  description = "EC2 instance type for the application"
  type        = string
  default     = "t3.micro"
}

variable "app_desired_count" {
  description = "Desired number of application instances"
  type        = number
  default     = 2
}

variable "app_min_count" {
  type    = number
  default = 1
}

variable "app_max_count" {
  type    = number
  default = 3
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for the monitoring stack"
  type        = string
  default     = "t3.small"
}

# ── Database ─────────────────────────────────────────────────────
variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

# ── Monitoring / Alerting ────────────────────────────────────────
variable "alert_email" {
  description = "Email address for SNS alert notifications"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

# ── ECR ──────────────────────────────────────────────────────────
variable "ecr_repository_name" {
  type    = string
  default = "fullstack-deploy-api"
}
