# ── Random password ──────────────────────────────────────────────
resource "random_password" "db" {
  length  = 24
  special = false
}

# ── Store password in Secrets Manager ────────────────────────────
resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "${var.project_name}-${var.environment}-db-"
  description = "RDS master password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

# ── DB Subnet Group ─────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-"
  subnet_ids  = var.db_subnets

  tags = { Name = "${var.project_name}-${var.environment}-db-subnet-group" }
}

# ── RDS Instance ─────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier_prefix = "${var.project_name}-${var.environment}-"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_groups

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true
  storage_encrypted   = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  performance_insights_enabled = true

  tags = { Name = "${var.project_name}-${var.environment}-db" }
}
