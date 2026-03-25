# ADR-002: Prometheus + Grafana + AlertManager Monitoring Stack

## Status
Accepted

## Context
We need an observability stack that provides metrics collection, visualization, and alerting for both application and infrastructure metrics. Options considered:
- Prometheus + Grafana + AlertManager (self-hosted)
- AWS CloudWatch only
- Datadog / New Relic (SaaS)
- ELK Stack (Elasticsearch + Logstash + Kibana)

## Decision
Use a **hybrid approach**: self-hosted **Prometheus + Grafana + AlertManager** on a dedicated EC2 instance, combined with **AWS CloudWatch** for infrastructure-level alarms and log aggregation.

## Rationale

**Prometheus + Grafana:**
- Industry standard for cloud-native monitoring
- Pull-based model scales well with dynamic targets (EC2 auto-discovery)
- PromQL is powerful and widely known
- Grafana provides best-in-class dashboarding
- No per-host or per-metric licensing costs
- Demonstrates real-world SRE skills

**CloudWatch (complementary):**
- Native integration with AWS services (ALB, RDS, EC2)
- Built-in metric alarms without additional infrastructure
- Log aggregation from EC2 instances via CloudWatch Agent
- SNS integration for email/Slack notifications

**Why not CloudWatch only:**
- Limited PromQL-like querying
- Dashboard flexibility inferior to Grafana
- No built-in equivalent to AlertManager routing
- Less transferable skill (vendor-specific)

**Why not SaaS (Datadog/New Relic):**
- Significant cost at scale ($15–$23/host/month)
- Overkill for this project scope
- Doesn't demonstrate self-hosted operations skills

## Consequences
- **Positive:** Full control, no per-metric costs, industry-standard tooling, demonstrates SRE competence
- **Negative:** Operational overhead of maintaining monitoring EC2 instance
- **Mitigation:** Monitoring instance is automated via Terraform + Docker Compose; can be replaced with managed services if needed
