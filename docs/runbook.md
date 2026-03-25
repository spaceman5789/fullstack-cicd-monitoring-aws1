# Runbook — Fullstack Deploy AWS

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Access & Credentials](#access--credentials)
3. [Deployment](#deployment)
4. [Rollback](#rollback)
5. [Monitoring](#monitoring)
6. [Incident Response](#incident-response)
7. [Common Tasks](#common-tasks)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
Internet → ALB (port 80) → App EC2 (ASG, private subnet, port 8000) → RDS PostgreSQL (private subnet)
                                 ↓
                        NAT Gateway (outbound)
                                 ↓
Monitoring EC2 (public subnet): Prometheus :9090, Grafana :3000, AlertManager :9093
```

**Components:**
- **ALB** — Application Load Balancer in public subnets, HTTP listener on port 80
- **App EC2 (ASG)** — Auto Scaling Group in private subnets, 2 instances (prod)
- **RDS PostgreSQL** — db.t3.small in private subnets, encrypted, 7-day backups
- **ECR** — Docker image registry with lifecycle policy (keeps 10 images)
- **Monitoring EC2** — Dedicated instance running Prometheus + Grafana + AlertManager
- **CloudWatch** — Log aggregation + metric alarms
- **SNS** — Alert notifications via email and Slack

---

## Access & Credentials

| Resource | How to access |
|----------|--------------|
| Application | `http://<ALB_DNS>/` |
| Grafana | `http://<MONITORING_IP>:3000` (admin/admin) |
| Prometheus | `http://<MONITORING_IP>:9090` |
| AlertManager | `http://<MONITORING_IP>:9093` |
| RDS | Not publicly accessible. Connect via app EC2 or SSM Session Manager |
| EC2 instances | SSM Session Manager (no SSH key required) |

**Get resource IPs:**
```bash
# ALB DNS
terraform -chdir=terraform output alb_dns_name

# Monitoring IP
terraform -chdir=terraform output monitoring_public_ip

# RDS endpoint
terraform -chdir=terraform output db_endpoint
```

**DB password:**
```bash
aws secretsmanager get-secret-value \
  --secret-id fullstack-deploy-prod-db-<id> \
  --region eu-north-1 \
  --query SecretString --output text
```

---

## Deployment

### Automatic (via GitLab CI/CD)
1. Create a Merge Request to `main` → pipeline runs tests + terraform plan (posted as MR note)
2. Review the plan in the MR comment
3. Merge to `main` → pipeline builds image, pushes to ECR, deploys to staging automatically
4. Trigger production deployment manually in the GitLab pipeline UI (deploy-prod job)

### Manual
```bash
# 1. Build and push image
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin <ECR_URL>
docker build -t <ECR_URL>:$(git rev-parse --short HEAD) ./app
docker push <ECR_URL>:$(git rev-parse --short HEAD)
docker tag <ECR_URL>:$(git rev-parse --short HEAD) <ECR_URL>:latest
docker push <ECR_URL>:latest

# 2. Trigger rolling deploy
./scripts/deploy.sh
```

### Verify deployment
```bash
# Check health
./scripts/health-check.sh

# Check ALB target health
curl http://<ALB_DNS>/health

# Check Grafana for errors
open http://<MONITORING_IP>:3000
```

---

## Rollback

### Quick rollback (previous version)
```bash
./scripts/rollback.sh
```

### Rollback to specific version
```bash
# List available launch template versions
aws ec2 describe-launch-template-versions \
  --launch-template-id <LT_ID> \
  --query "LaunchTemplateVersions[].{Version:VersionNumber,Created:CreateTime}" \
  --output table

# Set specific version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <ASG_NAME> \
  --launch-template "LaunchTemplateId=<LT_ID>,Version=<VERSION>"

# Trigger refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name <ASG_NAME>
```

### Terraform rollback
```bash
# Check git history for the last working state
git log --oneline terraform/

# Revert and apply
git revert <commit>
cd terraform && terraform apply -var-file=environments/prod/terraform.tfvars
```

---

## Monitoring

### Dashboards

| Dashboard | URL | Shows |
|-----------|-----|-------|
| App Overview | Grafana → App Overview | Request rate, error rate, latency p50/p95/p99, active requests |
| System Metrics | Grafana → System Metrics | CPU, memory, disk, network, load |

### Key Metrics

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Error rate (5xx) | < 1% | 1–5% | > 5% |
| p95 latency | < 200ms | 200ms–1s | > 1s |
| CPU usage | < 60% | 60–80% | > 80% |
| Memory usage | < 70% | 70–85% | > 85% |
| Disk usage | < 70% | 70–85% | > 85% |
| DB connections | < 50 | 50–80 | > 80 |

### Alert Channels
- **Email** — via SNS topic subscription
- **Slack** — via SNS → Lambda → Slack webhook
- **Prometheus alerts** — via AlertManager (HighErrorRate, HighLatency, InstanceDown, HighCPU, HighMemory, DiskSpaceLow)
- **CloudWatch alarms** — ALB 5xx, ALB latency, ASG CPU, RDS CPU, RDS connections, RDS storage

---

## Incident Response

### High Error Rate (> 5%)
1. Check Grafana → App Overview → Error Rate panel
2. Check application logs: `aws logs tail /<project>/prod/app --follow`
3. Check if RDS is available: `./scripts/health-check.sh`
4. If DB issue → check RDS console for CPU/connections/storage
5. If app issue → rollback: `./scripts/rollback.sh`

### High Latency (p95 > 1s)
1. Check Grafana → App Overview → Latency panel
2. Check if issue is DB-related (slow queries)
3. Check ASG instance count — scale up if needed
4. Check CloudWatch for ALB request count spikes

### Instance Down
1. Check ASG desired count vs running count
2. Check EC2 instance status checks in AWS console
3. Check CloudWatch logs for crash loops
4. ASG will auto-replace unhealthy instances

### RDS Issues
1. Check RDS console → Monitoring tab
2. If high CPU → check for long-running queries
3. If high connections → check for connection leaks in app
4. If low storage → increase `allocated_storage` in terraform.tfvars

---

## Common Tasks

### Scale application
```bash
# Temporary (resets on next terraform apply)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <ASG_NAME> \
  --desired-capacity 4 --min-size 2 --max-size 6

# Permanent
# Edit terraform/environments/prod/terraform.tfvars
# Then: terraform apply
```

### Update monitoring configs
```bash
./scripts/setup-monitoring.sh <MONITORING_IP> ~/.ssh/key.pem
```

### View application logs
```bash
aws logs tail /fullstack-deploy/prod/app --follow --region eu-north-1
```

### Connect to RDS (via EC2)
```bash
# Start SSM session to an app instance
aws ssm start-session --target <INSTANCE_ID>

# Then inside the instance:
docker exec -it app python -c "
import psycopg2
conn = psycopg2.connect(host='<RDS_ENDPOINT>', dbname='appdb', user='dbadmin', password='<PASSWORD>')
cur = conn.cursor()
cur.execute('SELECT count(*) FROM items')
print(cur.fetchone())
"
```

---

## Troubleshooting

### Deployment stuck
```bash
# Check instance refresh status
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name <ASG_NAME> \
  --query "InstanceRefreshes[0]"

# Cancel if needed
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name <ASG_NAME>
```

### Container not starting
```bash
# SSH into instance via SSM
aws ssm start-session --target <INSTANCE_ID>

# Check Docker
sudo docker ps -a
sudo docker logs app
sudo journalctl -u docker
```

### Terraform state lock
```bash
# List locks
aws dynamodb scan --table-name terraform-lock

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```
