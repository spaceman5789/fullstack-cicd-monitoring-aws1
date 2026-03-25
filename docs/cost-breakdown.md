# Cost Breakdown — AWS Resources

Estimated monthly costs for `eu-north-1` (Stockholm) region.

## Staging Environment

| Resource | Type | Cost/month |
|----------|------|-----------|
| EC2 App (ASG) | 1 × t3.micro | ~$8 |
| EC2 Monitoring | 1 × t3.micro | ~$8 |
| RDS PostgreSQL | db.t3.micro, 20 GB | ~$15 |
| ALB | Application LB | ~$18 |
| NAT Gateway | Single AZ | ~$35 |
| ECR | ~500 MB storage | ~$0.05 |
| CloudWatch | Logs + 6 alarms | ~$5 |
| SNS | Email notifications | ~$0 |
| S3 (TF state) | < 1 MB | ~$0.02 |
| Secrets Manager | 1 secret | ~$0.40 |
| **Total Staging** | | **~$90/month** |

## Production Environment

| Resource | Type | Cost/month |
|----------|------|-----------|
| EC2 App (ASG) | 2 × t3.small | ~$30 |
| EC2 Monitoring | 1 × t3.small | ~$15 |
| RDS PostgreSQL | db.t3.small, 50 GB | ~$28 |
| ALB | Application LB | ~$18 |
| NAT Gateway | Single AZ | ~$35 |
| ECR | ~1 GB storage | ~$0.10 |
| CloudWatch | Logs + 6 alarms | ~$8 |
| SNS + Lambda | Email + Slack | ~$1 |
| S3 (TF state) | < 1 MB | ~$0.02 |
| Secrets Manager | 1 secret | ~$0.40 |
| **Total Production** | | **~$136/month** |

## Cost Optimization Notes

1. **NAT Gateway** is the largest single cost (~$35). Can be replaced with NAT instances (t3.micro ~$8) for non-production.
2. **RDS** — Single-AZ is used. Multi-AZ doubles the cost but adds failover capability.
3. **Reserved Instances** — For production, 1-year RIs can save 30-40% on EC2 and RDS.
4. **Spot Instances** — ASG can mix spot instances for non-critical workloads (50-70% savings).
5. **Monitoring instance** — Could be replaced with managed Grafana ($9/month) + managed Prometheus in production.
6. **ALB** — Cost scales with traffic. Baseline is ~$18 + $0.008 per LCU-hour.

## Free Tier Eligible (first 12 months)

- 750 hours/month t3.micro (EC2)
- 750 hours/month db.t3.micro (RDS)
- 15 GB/month data transfer out
- 5 GB S3 storage
- 10 CloudWatch alarms
