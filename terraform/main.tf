# =====================================================================
# Root module — orchestrates all infrastructure modules
# =====================================================================

# ── Networking ───────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
}

# ── Security Groups ─────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "ALB — allow HTTP/HTTPS from internet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-app-"
  description = "App EC2 — allow traffic from ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "RDS — allow PostgreSQL from app instances only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "monitoring" {
  name_prefix = "${var.project_name}-mon-"
  description = "Monitoring EC2 — Grafana, Prometheus, AlertManager"
  vpc_id      = module.vpc.vpc_id

  # Grafana
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # AlertManager
  ingress {
    description = "AlertManager"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (restrict in production)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── ECR ──────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  repository_name = var.ecr_repository_name
  project_name    = var.project_name
  environment     = var.environment
}

# ── ALB ──────────────────────────────────────────────────────────
module "alb" {
  source = "./modules/alb"

  project_name    = var.project_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnet_ids
  security_groups = [aws_security_group.alb.id]
}

# ── Compute (App EC2 / ASG) ─────────────────────────────────────
module "ec2" {
  source = "./modules/ec2"

  project_name       = var.project_name
  environment        = var.environment
  instance_type      = var.app_instance_type
  desired_capacity   = var.app_desired_count
  min_size           = var.app_min_count
  max_size           = var.app_max_count
  private_subnets    = module.vpc.private_app_subnet_ids
  security_groups    = [aws_security_group.app.id]
  target_group_arn   = module.alb.target_group_arn
  ecr_repository_url = module.ecr.repository_url
  db_endpoint        = module.rds.db_endpoint
  db_name            = var.db_name
  db_username        = var.db_username
  db_secret_arn      = module.rds.db_secret_arn
  aws_region         = var.aws_region
}

# ── Database (RDS) ───────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  project_name      = var.project_name
  environment       = var.environment
  db_name           = var.db_name
  db_username       = var.db_username
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  db_subnets        = module.vpc.private_db_subnet_ids
  security_groups   = [aws_security_group.rds.id]
}

# ── Monitoring (Prometheus + Grafana + AlertManager) ─────────────
module "monitoring" {
  source = "./modules/monitoring"

  project_name    = var.project_name
  environment     = var.environment
  instance_type   = var.monitoring_instance_type
  subnet_id       = module.vpc.public_subnet_ids[0]
  security_groups = [aws_security_group.monitoring.id]
  aws_region      = var.aws_region
}

# ── CloudWatch ───────────────────────────────────────────────────
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  asg_name           = module.ec2.asg_name
  alb_arn_suffix     = module.alb.alb_arn_suffix
  tg_arn_suffix      = module.alb.target_group_arn_suffix
  db_instance_id     = module.rds.db_instance_id
  sns_topic_arn      = module.sns.topic_arn
}

# ── SNS (Alerting) ───────────────────────────────────────────────
module "sns" {
  source = "./modules/sns"

  project_name      = var.project_name
  environment       = var.environment
  alert_email       = var.alert_email
  slack_webhook_url = var.slack_webhook_url
}
