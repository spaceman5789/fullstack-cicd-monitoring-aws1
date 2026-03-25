# ── Application Load Balancer ────────────────────────────────────
resource "aws_lb" "main" {
  name_prefix        = "app-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_groups
  subnets            = var.public_subnets

  tags = { Name = "${var.project_name}-${var.environment}-alb" }
}

# ── Target Group ─────────────────────────────────────────────────
resource "aws_lb_target_group" "app" {
  name_prefix = "app-"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-${var.environment}-tg" }
}

# ── HTTP Listener ────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
