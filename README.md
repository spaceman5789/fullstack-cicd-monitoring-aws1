# Full-Stack Deploy: Terraform + GitLab CI/CD + Monitoring

> Complete automation from commit to production on AWS with monitoring and alerting.

This project demonstrates an **end-to-end DevOps pipeline**: infrastructure is provisioned via Terraform, code is delivered through GitLab CI/CD, and Prometheus + Grafana + AlertManager monitor system health 24/7.

---

## What This Project Does

1. **You push code** → GitLab automatically runs tests, linters, and security scanners
2. **You create a Merge Request** → GitLab posts `terraform plan` as an MR comment — showing exactly what AWS resources will change
3. **You merge to main** → Docker image is built, pushed to ECR, Terraform updates infrastructure, app rolls out to staging automatically
4. **You click a button** → production deployment (manual trigger — protection against accidental rollouts)
5. **Monitoring** → Grafana dashboards show latency, error rate, CPU/memory. If something breaks — alert via email and Slack

**Zero manual steps** between commit and production (except the final confirmation).

---

## Architecture

```
                    ┌───────────────────────────────────────────────────┐
                    │                  AWS VPC 10.0.0.0/16              │
                    │                                                   │
                    │   Public Subnets                                  │
                    │   ┌─────────────┐       ┌──────────────────┐     │
  Internet ────────►│   │     ALB     │       │  Monitoring EC2  │     │
                    │   │   (HTTP:80) │       │                  │     │
                    │   └──────┬──────┘       │  Prometheus:9090 │     │
                    │          │              │  Grafana:3000    │     │
                    │          │              │  AlertManager:9093│     │
                    │          │              └──────────────────┘     │
                    │          ▼                                        │
                    │   Private App Subnets                             │
                    │   ┌─────────────────────────────┐                │
                    │   │   EC2 Auto Scaling Group     │                │
                    │   │                              │                │
                    │   │  ┌──────────┐ ┌──────────┐  │                │
                    │   │  │ App EC2  │ │ App EC2  │  │                │
                    │   │  │  :8000   │ │  :8000   │  │                │
                    │   │  └──────────┘ └──────────┘  │                │
                    │   └──────────────┬──────────────┘                │
                    │                  │                                │
                    │          NAT Gateway (outbound internet)          │
                    │                  │                                │
                    │                  ▼                                │
                    │   Private DB Subnets                              │
                    │   ┌─────────────────────────────┐                │
                    │   │    RDS PostgreSQL 16         │                │
                    │   │    (db.t3.small, encrypted)  │                │
                    │   └─────────────────────────────┘                │
                    └───────────────────────────────────────────────────┘
```

### Traffic Flow

```
User → ALB (port 80) → EC2 instance (port 8000) → RDS PostgreSQL (port 5432)
```

- **ALB** accepts HTTP requests from the internet and distributes them across EC2 instances
- **EC2 instances** reside in private subnets — no direct internet access
- **RDS** is also in a private subnet — only accessible from app EC2 instances
- **NAT Gateway** allows private instances to reach the internet (for updates and pulling Docker images)

### Security (Security Groups)

```
ALB SG:  accepts HTTP/HTTPS from 0.0.0.0/0 (entire internet)
     ↓
App SG:  accepts port 8000 ONLY from ALB SG
     ↓
RDS SG:  accepts port 5432 ONLY from App SG
```

Each layer is only accessible from the previous one. The database cannot be reached from the internet.

---

## CI/CD Pipeline (GitLab)

### On Merge Request

GitLab runs checks **before code reaches main**:

| Job | What it does | Why |
|-----|-------------|-----|
| `lint` | Code check with ruff linter | Consistent code style |
| `dockerfile-lint` | Dockerfile check (hadolint) | Docker best practices |
| `terraform-validate` | `terraform fmt` + `validate` | Terraform code correctness |
| `tfsec` | Terraform security scan | Infrastructure security |
| `test` | Pytest + coverage report | Code works, coverage visible in MR |
| `docker-build` | Build Docker image | Dockerfile compiles without errors |
| `trivy-scan` | Container image CVE scan | No critical vulnerabilities |
| `terraform-plan` | Plan + comment in MR | See what will change in AWS |

### On Merge to Main

```
test → build-push-ecr → terraform-apply-staging → deploy-staging → [terraform-apply-prod] → [deploy-prod] → notify
                                                                    └── manual trigger ──┘
```

| Job | What it does | Automatic? |
|-----|-------------|------------|
| `build-push-ecr` | Build Docker image, push to ECR (tags: SHA, latest, branch) | Yes |
| `terraform-apply-staging` | Apply Terraform for staging environment | Yes |
| `deploy-staging` | Roll out new version to staging via ASG instance refresh | Yes |
| `terraform-apply-prod` | Apply Terraform for production | **No — manual button** |
| `deploy-prod` | Roll out to production | **No — manual button** |
| `notify-success/failure` | Send notification via SNS | Yes |

### Pipeline Visualization

```
┌──────────┐   ┌──────┐   ┌───────┐   ┌─────────────────────┐   ┌────────┐
│ validate │──►│ test │──►│ build │──►│ deploy              │──►│ notify │
│          │   │      │   │       │   │                     │   │        │
│ lint     │   │pytest│   │docker │   │ staging (auto)      │   │ SNS    │
│ hadolint │   │trivy │   │push   │   │ production (manual) │   │ email  │
│ tf valid │   │build │   │to ECR │   │                     │   │ slack  │
│ tfsec    │   │plan  │   │       │   │                     │   │        │
└──────────┘   └──────┘   └───────┘   └─────────────────────┘   └────────┘
```

---

## Application

REST API built with **FastAPI** (Python 3.12) featuring CRUD operations and built-in Prometheus metrics.

### Endpoints

| Method | URL | Description |
|--------|-----|-------------|
| GET | `/` | Service info (version, environment) |
| GET | `/health` | Liveness probe — always returns 200 if the process is alive |
| GET | `/ready` | Readiness probe — checks database connectivity |
| GET | `/api/items` | List all records |
| POST | `/api/items` | Create a record `{"name": "...", "description": "..."}` |
| GET | `/api/items/{id}` | Get record by ID |
| DELETE | `/api/items/{id}` | Delete record |
| GET | `/metrics` | Prometheus metrics |

### Metrics Collected by the Application

| Metric | Type | What it measures |
|--------|------|-----------------|
| `http_requests_total` | Counter | Total requests (by method, endpoint, status code) |
| `http_request_duration_seconds` | Histogram | Response time (p50, p95, p99) |
| `http_active_requests` | Gauge | Requests being processed right now |
| `db_connection_errors_total` | Counter | Database connection errors |
| `app_info` | Gauge | Application version and environment |

### Docker Image

- **Multi-stage build** — build dependencies don't end up in the final image
- **Non-root user** — container runs as `appuser`, not root
- **HEALTHCHECK** — Docker monitors container health automatically
- Base image: `python:3.12-slim`

---

## Terraform — Infrastructure as Code

All AWS infrastructure is defined in **8 modules**. Each module handles its own layer:

### Modules

| Module | What it creates | Key resources |
|--------|----------------|--------------|
| **vpc** | Networking | VPC, 6 subnets (2 public + 2 app + 2 db), Internet Gateway, NAT Gateway, Route Tables |
| **ec2** | Compute | Launch Template, Auto Scaling Group (min 1 / max 4), IAM Role (ECR pull + Secrets Manager + CloudWatch) |
| **rds** | Database | PostgreSQL 16, Secrets Manager (password), DB Subnet Group, 7-day backups |
| **ecr** | Image registry | ECR Repository, Lifecycle Policy (keeps last 10 images) |
| **alb** | Load balancer | ALB, Target Group, HTTP Listener, Health Check (/health) |
| **monitoring** | Monitoring | EC2 instance with Docker Compose (Prometheus + Grafana + AlertManager + node-exporter) |
| **cloudwatch** | Logs & alarms | Log Group, 6 metric alarms (ALB 5xx, ALB latency, ASG CPU, RDS CPU, RDS connections, RDS storage) |
| **sns** | Notifications | SNS Topic, email subscription, Lambda for Slack |

### Environments

```
terraform/environments/
├── staging/terraform.tfvars    # 1 × t3.micro, db.t3.micro, 20 GB
└── prod/terraform.tfvars       # 2 × t3.small, db.t3.small, 50 GB
```

### Terraform State

- Stored in **S3** (encrypted, versioned)
- Locking via **DynamoDB** — two people cannot run `terraform apply` simultaneously

---

## Monitoring & Alerting

### Monitoring Stack

A dedicated EC2 instance runs 4 containers:

```
┌─────────────────────────────────────────────────────┐
│               Monitoring EC2 Instance                │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │  Prometheus   │  │   Grafana    │                 │
│  │  :9090        │  │   :3000      │                 │
│  │              ◄├──┤  (dashboards)│                 │
│  │  scrapes:     │  └──────────────┘                 │
│  │  - app:8000   │                                   │
│  │  - node:9100  │  ┌──────────────┐                 │
│  │               │  │ AlertManager │                 │
│  │              ─├──►  :9093       │                 │
│  └──────────────┘  └──────────────┘                 │
│                                                      │
│  ┌──────────────┐                                    │
│  │node-exporter │  Collects CPU, RAM, disk           │
│  │  :9100       │  from the host itself              │
│  └──────────────┘                                    │
└─────────────────────────────────────────────────────┘
```

**Prometheus** scrapes every 15 seconds:
- All app EC2 instances (auto-discovery by `Name` tag) — application metrics
- node-exporter on each instance — system metrics (CPU, RAM, disk, network)

### Grafana Dashboards (exported JSON)

**Application Overview** — application health:
- Request Rate (req/s by endpoint)
- Error Rate (% of 4xx and 5xx errors)
- Latency p50 / p95 / p99 (response time)
- Active Requests (requests being processed right now)
- DB Connection Errors
- Requests by Status Code (pie chart)

**System Metrics** — server health:
- CPU Usage % (per instance)
- Memory Usage % (per instance)
- Disk Usage % (gauge)
- Network I/O (inbound/outbound traffic)
- System Load (1m / 5m / 15m)
- Open File Descriptors

### Alerts

Dual alerting system — Prometheus + CloudWatch:

**Prometheus → AlertManager:**

| Alert | Threshold | Severity |
|-------|-----------|----------|
| High Error Rate | 5xx > 5% for 2 min | Critical |
| High Latency p95 | > 1s for 3 min | Warning |
| High Latency p99 | > 2.5s for 3 min | Critical |
| Instance Down | up == 0 for 1 min | Critical |
| High CPU | > 80% for 5 min | Warning |
| High Memory | > 85% for 5 min | Warning |
| Disk Space Low | > 85% for 5 min | Warning |

**CloudWatch → SNS → Email/Slack:**

| Alert | Threshold |
|-------|-----------|
| ALB 5xx Count | > 10 in 5 min |
| ALB Latency p95 | > 2s for 15 min |
| ASG CPU | > 80% for 15 min |
| RDS CPU | > 80% for 15 min |
| RDS Connections | > 80 |
| RDS Free Storage | < 2 GB |

---

## Project Structure

```
.
├── .gitlab-ci.yml                  # GitLab CI/CD: 5 stages, 13 jobs
│
├── app/                            # Application
│   ├── src/main.py                 #   FastAPI + Prometheus metrics (220 lines)
│   ├── tests/test_main.py          #   10 unit tests (pytest)
│   ├── Dockerfile                  #   Multi-stage, non-root, HEALTHCHECK
│   ├── requirements.txt            #   fastapi, uvicorn, psycopg2, prometheus-client
│   └── requirements-dev.txt        #   pytest, httpx, coverage
│
├── terraform/                      # Infrastructure (Terraform)
│   ├── main.tf                     #   Root module + Security Groups
│   ├── variables.tf                #   All variables
│   ├── outputs.tf                  #   VPC ID, ALB DNS, Grafana URL, etc.
│   ├── providers.tf                #   AWS provider + default tags
│   ├── backend.tf                  #   S3 remote state + DynamoDB lock
│   ├── modules/
│   │   ├── vpc/                    #   Networking (VPC, subnets, NAT, IGW)
│   │   ├── ec2/                    #   Compute (ASG, Launch Template, IAM, user_data)
│   │   ├── rds/                    #   Database (PostgreSQL, Secrets Manager)
│   │   ├── ecr/                    #   Docker registry (lifecycle policy)
│   │   ├── alb/                    #   Load balancer (Target Group, Listener)
│   │   ├── monitoring/             #   Monitoring server (Docker Compose inside)
│   │   ├── cloudwatch/             #   Logs + 6 alarms
│   │   └── sns/                    #   Email + Slack Lambda
│   └── environments/
│       ├── staging/terraform.tfvars
│       └── prod/terraform.tfvars
│
├── monitoring/                     # Monitoring configs
│   ├── prometheus/
│   │   ├── prometheus.yml          #   Scrape config (app + node-exporter)
│   │   └── alerts.yml              #   7 alert rules
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   ├── app-overview.json   #   Application dashboard (7 panels)
│   │   │   └── system-metrics.json #   System dashboard (7 panels)
│   │   └── provisioning/           #   Auto-provisioning datasource + dashboards
│   └── alertmanager/
│       └── alertmanager.yml        #   Routing rules
│
├── scripts/                        # Operational scripts
│   ├── deploy.sh                   #   Rolling deploy via ASG instance refresh
│   ├── rollback.sh                 #   Rollback to previous Launch Template version
│   ├── health-check.sh             #   Check all components (ALB, TG, RDS, CW)
│   └── setup-monitoring.sh         #   Upload configs to monitoring server
│
├── docs/                           # Documentation
│   ├── runbook.md                  #   Operations guide: deploy, rollback, incidents
│   ├── cost-breakdown.md           #   AWS resource cost breakdown
│   └── adr/                        #   Architecture Decision Records
│       ├── 001-gitlab-cicd.md      #     Why GitLab CI over Jenkins/GitHub Actions
│       ├── 002-monitoring-stack.md #     Why Prometheus+Grafana over CloudWatch only
│       └── 003-vpc-network-design.md #   Why 3-tier VPC with two AZs
│
├── docker-compose.yml              # Local dev (app + PG + Prometheus + Grafana)
├── Makefile                        # Shortcuts (make dev, make test, make deploy)
├── .env.example                    # Environment variables template
└── .gitignore
```

---

## Quick Start

### Local Development

```bash
# 1. Copy environment variables
cp .env.example .env

# 2. Start everything with one command
make dev

# 3. Open in browser:
#    Application:   http://localhost:8000
#    Grafana:       http://localhost:3000  (login: admin / password: admin)
#    Prometheus:    http://localhost:9090
#    AlertManager:  http://localhost:9093

# 4. Test the API
curl http://localhost:8000/health
curl http://localhost:8000/api/items
curl -X POST http://localhost:8000/api/items -H "Content-Type: application/json" -d '{"name":"test"}'
```

### Run Tests

```bash
make test    # pytest + coverage
make lint    # ruff (linter)
```

### Deploy to AWS

**Prerequisites:**
1. AWS account with an IAM user (permissions for EC2, RDS, ECR, ALB, VPC, CloudWatch, SNS, Secrets Manager, S3, DynamoDB)
2. S3 bucket for Terraform state (`fullstack-deploy-tfstate`)
3. DynamoDB table for state locking (`terraform-lock`)
4. GitLab repository with CI/CD Variables configured

```bash
# Manual deploy (without CI/CD):

# 1. Review the plan
make plan

# 2. Apply infrastructure
make apply

# 3. Build and push Docker image to ECR
make push

# 4. Roll out application (rolling update via ASG)
make deploy

# 5. Verify everything works
make health
```

### GitLab CI/CD Variables

Configure in **Settings → CI/CD → Variables** (mark as masked + protected):

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | IAM access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key (masked) | `wJal...` |
| `ALERT_EMAIL` | Email for alerts | `alerts@example.com` |
| `SLACK_WEBHOOK_URL` | Slack webhook (optional) | `https://hooks.slack.com/...` |
| `SNS_TOPIC_ARN` | SNS topic ARN for notifications | `arn:aws:sns:eu-north-1:...` |
| `GITLAB_API_TOKEN` | For posting MR comments | `glpat-...` |

---

## AWS Resource Costs

| Environment | Monthly Cost | Main Expenses |
|-------------|-------------|--------------|
| **Staging** | ~$90 | NAT Gateway ($35), ALB ($18), RDS ($15), EC2 ($8) |
| **Production** | ~$136 | NAT Gateway ($35), EC2 x2 ($30), RDS ($28), ALB ($18) |

Detailed breakdown: [docs/cost-breakdown.md](docs/cost-breakdown.md)

---

## Makefile Commands

| Command | What it does |
|---------|-------------|
| `make dev` | Start local environment (app + DB + monitoring) |
| `make down` | Stop everything |
| `make test` | Run tests |
| `make lint` | Check code with linter |
| `make build` | Build Docker image |
| `make plan` | Terraform plan |
| `make apply` | Terraform apply |
| `make deploy` | Rolling deploy to AWS |
| `make rollback` | Roll back to previous version |
| `make health` | Check health of all components |
| `make clean` | Remove all containers, volumes, images |

---

## Tech Stack

| Category | Technologies |
|----------|-------------|
| **Application** | Python 3.12, FastAPI, Uvicorn, psycopg2, prometheus-client |
| **Testing** | pytest, pytest-cov, httpx, ruff |
| **Containerization** | Docker (multi-stage), Docker Compose |
| **CI/CD** | GitLab CI/CD (5 stages, 13 jobs), Docker-in-Docker |
| **Infrastructure** | Terraform 1.7+ (8 modules), AWS (EC2, ALB, RDS, ECR, VPC, S3) |
| **Monitoring** | Prometheus, Grafana 10, AlertManager, node-exporter |
| **Logs & Alarms** | CloudWatch Logs, CloudWatch Alarms |
| **Notifications** | SNS, Lambda (Slack webhook) |
| **Security** | Secrets Manager, tfsec, Trivy, hadolint, Security Groups |

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/runbook.md](docs/runbook.md) | Operations guide: deploy, rollback, incidents, troubleshooting |
| [docs/cost-breakdown.md](docs/cost-breakdown.md) | AWS resource cost breakdown for staging and production |
| [docs/adr/001-gitlab-cicd.md](docs/adr/001-gitlab-cicd.md) | ADR: why GitLab CI/CD was chosen |
| [docs/adr/002-monitoring-stack.md](docs/adr/002-monitoring-stack.md) | ADR: why Prometheus + Grafana + CloudWatch |
| [docs/adr/003-vpc-network-design.md](docs/adr/003-vpc-network-design.md) | ADR: why 3-tier VPC with two AZs |

---

## Related Projects

This project integrates and builds upon three previous ones:

| # | Project | What it demonstrates | What was taken into project 6 |
|---|---------|---------------------|------------------------------|
| 3 | [aws-infrastructure-terraform](https://github.com/spaceman5789/aws-infrastructure-terraform) | Terraform modules (VPC, EC2, RDS) | Modular structure, Security Groups, remote state |
| 4 | [gitlab-ci-ec2-deploy](https://github.com/spaceman5789/gitlab-ci-ec2-deploy) | GitLab CI/CD pipeline | Multi-stage pipeline, Docker build, deploy via SSH |
| 5 | [multi-service-observability-stack](https://github.com/spaceman5789/multi-service-observability-stack) | Prometheus + Grafana monitoring | Scrape configs, Grafana dashboards, alert rules |
| **6** | **This project** | **Everything combined** | Terraform + GitLab CI/CD + monitoring + CloudWatch + SNS |
