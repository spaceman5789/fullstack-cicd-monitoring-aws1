# ── IAM Role for EC2 (ECR pull + Secrets Manager + CloudWatch) ───
resource "aws_iam_role" "app" {
  name_prefix = "${var.project_name}-app-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "app" {
  name_prefix = "${var.project_name}-app-"
  role        = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [var.db_secret_arn]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.project_name}-app-"
  role        = aws_iam_role.app.name
}

# ── Launch Template ──────────────────────────────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  vpc_security_group_ids = var.security_groups

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region         = var.aws_region
    ecr_repository_url = var.ecr_repository_url
    db_endpoint        = var.db_endpoint
    db_name            = var.db_name
    db_username        = var.db_username
    db_secret_arn      = var.db_secret_arn
    project_name       = var.project_name
    environment        = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}-app"
    }
  }
}

# ── Auto Scaling Group ───────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name_prefix         = "${var.project_name}-app-"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.private_subnets
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-app"
    propagate_at_launch = true
  }
}
