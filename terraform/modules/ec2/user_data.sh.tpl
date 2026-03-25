#!/bin/bash
set -euo pipefail

# ── Install Docker ───────────────────────────────────────────────
dnf update -y
dnf install -y docker aws-cli
systemctl enable docker
systemctl start docker

# ── Install CloudWatch Agent ─────────────────────────────────────
dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWEOF'
{
  "agent": { "run_as_user": "root" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "${project_name}-${environment}-app",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
CWEOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# ── Install node_exporter for Prometheus ─────────────────────────
useradd --no-create-home --shell /sbin/nologin node_exporter || true
curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz \
  | tar xz -C /tmp
cp /tmp/node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<'NEEOF'
[Unit]
Description=Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
[Install]
WantedBy=multi-user.target
NEEOF
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# ── Retrieve DB password from Secrets Manager ───────────────────
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString --output text)

# ── Log in to ECR ────────────────────────────────────────────────
aws ecr get-login-password --region "${aws_region}" \
  | docker login --username AWS --password-stdin "${ecr_repository_url}"

# ── Pull and run the application container ───────────────────────
mkdir -p /var/log/app

docker pull "${ecr_repository_url}:latest"

docker run -d \
  --name app \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /var/log/app:/var/log/app \
  -e DB_HOST="${db_endpoint}" \
  -e DB_PORT=5432 \
  -e DB_NAME="${db_name}" \
  -e DB_USER="${db_username}" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e APP_ENV="${environment}" \
  "${ecr_repository_url}:latest"
