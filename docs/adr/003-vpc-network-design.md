# ADR-003: VPC Network Design — 3-Tier Architecture

## Status
Accepted

## Context
We need a network architecture that balances security, availability, and cost for a web application with a database backend and monitoring stack.

## Decision
Deploy a **3-tier VPC architecture** across 2 Availability Zones in `eu-north-1`:

```
VPC 10.0.0.0/16
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   ├── ALB
│   ├── Monitoring EC2
│   ├── NAT Gateway
│   └── Internet Gateway
├── Private App Subnets (10.0.11.0/24, 10.0.12.0/24)
│   └── App EC2 instances (ASG)
└── Private DB Subnets (10.0.21.0/24, 10.0.22.0/24)
    └── RDS PostgreSQL
```

## Rationale

**Security layers:**
1. ALB SG → allows HTTP/HTTPS from internet
2. App SG → allows port 8000 from ALB SG only
3. RDS SG → allows port 5432 from App SG only
4. No direct internet access to app or DB instances

**Single NAT Gateway (cost vs. availability):**
- Full HA requires NAT Gateway per AZ (~$70/month total)
- Single NAT Gateway costs ~$35/month
- Acceptable trade-off: if the NAT AZ goes down, private instances lose outbound internet, but ALB traffic still works via the other AZ

**2 AZs (not 3):**
- eu-north-1 has 3 AZs, but 2 is sufficient for this project
- Reduces cost (fewer subnets, no extra NAT)
- Easy to extend to 3 AZs by adding CIDR blocks

## Consequences
- **Positive:** Defense-in-depth security, multi-AZ availability, clear network segmentation
- **Negative:** Single NAT Gateway is a partial SPOF for outbound traffic
- **Mitigation:** App traffic through ALB is unaffected; NAT is only needed for Docker pulls and OS updates (infrequent)
