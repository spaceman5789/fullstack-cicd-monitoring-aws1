# ── IAM Role for Monitoring EC2 ──────────────────────────────────
resource "aws_iam_role" "monitoring" {
  name_prefix = "${var.project_name}-mon-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "monitoring" {
  name_prefix = "${var.project_name}-mon-"
  role        = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2Describe"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
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

resource "aws_iam_instance_profile" "monitoring" {
  name_prefix = "${var.project_name}-mon-"
  role        = aws_iam_role.monitoring.name
}

# ── Latest Amazon Linux 2023 AMI ─────────────────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ── Monitoring EC2 Instance ──────────────────────────────────────
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_groups
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region   = var.aws_region
    project_name = var.project_name
    environment  = var.environment
  }))

  tags = { Name = "${var.project_name}-${var.environment}-monitoring" }
}
