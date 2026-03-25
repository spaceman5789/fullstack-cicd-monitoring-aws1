# Full-Stack Deploy: Terraform + GitLab CI/CD + Monitoring

End-to-end DevOps project: from `git push` to **production on AWS** with full observability.
Integrates infrastructure-as-code (Terraform), CI/CD (GitLab CI/CD), and monitoring (Prometheus + Grafana + AlertManager + CloudWatch).

## Architecture

```
                         ┌─────────────────────────────────────────────┐
                         │                   VPC 10.0.0.0/16          │
                         │                                             │
  Internet ──────────►   │  ┌──────────┐    Public Subnets             │
                         │  │   ALB    │──── 10.0.1.0/24               │
                         │  │  :80     │──── 10.0.2.0/24               │
                         │  └────┬─────┘                               │
                         │       │           ┌──────────────┐          │
                         │       │           │ Monitoring   │          │
                         │       │           │ EC2          │          │
                         │       │           │ :3000 Grafana│          │
                         │       │           │ :9090 Prom   │          │
                         │       │           │ :9093 Alert  │          │
                         │       │           └──────────────┘          │
                         │       ▼                                     │
                         │  ┌──────────┐    Private App Subnets        │
                         │  │ EC2 ASG  │──── 10.0.11.0/24              │
                         │  │ App :8000│──── 10.0.12.0/24              │
                         │  └────┬─────┘                               │
                         │       │     NAT GW ◄── outbound internet    │
                         │       ▼                                     │
                         │  ┌──────────┐    Private DB Subnets         │
                         │  │   RDS    │──── 10.0.21.0/24              │
                         │  │ PG :5432 │──── 10.0.22.0/24              │
                         │  └──────────┘                               │
                         └─────────────────────────────────────────────┘
```

## CI/CD Pipeline

```
Merge Request                           Merge to main
─────────────                           ─────────────
  │                                       │
  ├─ pytest + ruff lint                   ├─ pytest + docker build
  ├─ Dockerfile lint (hadolint)           ├─ Docker build → push to ECR
  ├─ Docker build + Trivy scan            ├─ Terraform apply (staging auto)
  ├─ Terraform fmt + validate             ├─ Deploy to staging (auto)
  ├─ tfsec security scan                  ├─ Terraform apply (prod manual)
  └─ Terraform plan → MR comment          ├─ Deploy to production (manual)
                                          └─ SNS notification
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Application | Python 3.12 / FastAPI / Uvicorn |
| Database | PostgreSQL 16 (RDS) |
| Container | Docker (multi-stage build) |
| Registry | AWS ECR |
| Infrastructure | Terraform 1.7+ (8 modules) |
| CI/CD | GitLab CI/CD (5 stages, 13 jobs) |
| Load Balancer | AWS ALB |
| Compute | EC2 Auto Scaling Group |
| Metrics | Prometheus + node_exporter |
| Dashboards | Grafana 10 (2 pre-built dashboards) |
| Alerting | AlertManager + CloudWatch Alarms + SNS |
| Logs | CloudWatch Logs |
| Notifications | SNS → Email + Lambda → Slack |
| Secrets | AWS Secrets Manager |

## Project Structure

```
.
├── .gitlab-ci.yml                  # 5-stage pipeline (validate → test → build → deploy → notify)
├── app/
│   ├── src/main.py               # FastAPI app with Prometheus metrics
│   ├── tests/test_main.py        # Unit tests (pytest)
│   ├── Dockerfile                # Multi-stage, non-root
│   └── requirements.txt
├── terraform/
│   ├── main.tf                   # Root module (orchestrates 8 modules)
│   ├── modules/
│   │   ├── vpc/                  # VPC, subnets, NAT, IGW
│   │   ├── ec2/                  # Launch template, ASG, IAM
│   │   ├── rds/                  # PostgreSQL, Secrets Manager
│   │   ├── ecr/                  # Container registry + lifecycle
│   │   ├── alb/                  # Load balancer, target group
│   │   ├── monitoring/           # Prometheus/Grafana EC2
│   │   ├── cloudwatch/           # Log groups, metric alarms
│   │   └── sns/                  # Topic, email, Slack Lambda
│   └── environments/
│       ├── staging/terraform.tfvars
│       └── prod/terraform.tfvars
├── monitoring/
│   ├── prometheus/               # prometheus.yml, alerts.yml
│   ├── grafana/                  # Dashboards JSON, provisioning
│   └── alertmanager/             # alertmanager.yml
├── scripts/
│   ├── deploy.sh                 # Rolling deploy via ASG
│   ├── rollback.sh               # Rollback to previous version
│   ├── health-check.sh           # Check all components
│   └── setup-monitoring.sh       # Upload configs to monitoring EC2
├── docs/
│   ├── runbook.md                # Operational procedures
│   ├── cost-breakdown.md         # AWS resource costs
│   └── adr/                      # Architecture Decision Records
│       ├── 001-gitlab-cicd.md
│       ├── 002-monitoring-stack.md
│       └── 003-vpc-network-design.md
├── docker-compose.yml            # Local dev (app + PG + monitoring)
├── Makefile                      # Developer shortcuts
└── README.md
```

## Quick Start

### Local Development
```bash
cp .env.example .env
make dev

# App:          http://localhost:8000
# Grafana:      http://localhost:3000  (admin/admin)
# Prometheus:   http://localhost:9090
```

### Run Tests
```bash
make test
make lint
```

### Deploy to AWS

**Prerequisites:**
- AWS CLI configured with appropriate permissions
- S3 bucket + DynamoDB table for Terraform state
- GitLab CI/CD variables configured (see below)

```bash
# 1. Review infrastructure
make plan

# 2. Apply infrastructure
make apply

# 3. Push Docker image
make push

# 4. Deploy application
make deploy

# 5. Check health
make health
```

### Required GitLab CI/CD Variables

Configure in **Settings → CI/CD → Variables** (masked + protected):

| Variable | Description |
|----------|-----------|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key (masked) |
| `ALERT_EMAIL` | Email for SNS notifications |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook (optional, masked) |
| `SNS_TOPIC_ARN` | SNS topic ARN for deploy notifications |
| `GITLAB_API_TOKEN` | GitLab API token for posting MR comments |
| `STAGING_ALB_DNS` | Staging ALB DNS name |
| `PROD_ALB_DNS` | Production ALB DNS name |

## Grafana Dashboards

### Application Overview
Request rate, error rate (4xx/5xx), latency (p50/p95/p99), active requests, DB errors, status code distribution.

### System Metrics
CPU usage, memory usage, disk usage, network I/O, system load, file descriptors.

## Alerting

| Alert | Threshold | Severity |
|-------|----------|----------|
| High Error Rate | 5xx > 5% for 2m | Critical |
| High Latency p95 | > 1s for 3m | Warning |
| High Latency p99 | > 2.5s for 3m | Critical |
| Instance Down | up == 0 for 1m | Critical |
| High CPU | > 80% for 5m | Warning |
| High Memory | > 85% for 5m | Warning |
| Disk Space Low | > 85% for 5m | Warning |
| ALB 5xx Count | > 10 in 5m | CloudWatch |
| ALB Latency p95 | > 2s for 15m | CloudWatch |
| RDS CPU | > 80% for 15m | CloudWatch |
| RDS Connections | > 80 | CloudWatch |
| RDS Free Storage | < 2 GB | CloudWatch |

## Cost Estimate

| Environment | Monthly Cost |
|-------------|-------------|
| Staging | ~$90 |
| Production | ~$136 |

See [docs/cost-breakdown.md](docs/cost-breakdown.md) for detailed breakdown.

## Related Projects

| # | Project | What it demonstrates |
|---|---------|---------------------|
| 3 | [aws-infrastructure-terraform](../aws-infrastructure-terraform) | Terraform modules (VPC, EC2, RDS) |
| 4 | [gitlab-ci-ec2-deploy](../gitlab-ci-ec2-deploy) | GitLab CI/CD pipeline |
| 5 | [multi-service-observability-stack](../multi-service-observability-stack) | Prometheus + Grafana monitoring |
| **6** | **This project** | **Integration of 3 + 4 + 5 with GitLab CI/CD** |
