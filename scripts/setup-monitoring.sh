#!/usr/bin/env bash
# setup-monitoring.sh — Copy monitoring configs to the monitoring EC2 instance
# Usage: ./scripts/setup-monitoring.sh <monitoring-ip> [ssh-key-path]
set -euo pipefail

MONITORING_IP="${1:?Usage: $0 <monitoring-ip> [ssh-key-path]}"
SSH_KEY="${2:-~/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-ec2-user}"
REMOTE_DIR="/opt/monitoring"

echo "==> Uploading monitoring configs to ${MONITORING_IP}"

# Upload Prometheus configs
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  monitoring/prometheus/prometheus.yml \
  monitoring/prometheus/alerts.yml \
  "${SSH_USER}@${MONITORING_IP}:${REMOTE_DIR}/prometheus/"

# Upload AlertManager config
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  monitoring/alertmanager/alertmanager.yml \
  "${SSH_USER}@${MONITORING_IP}:${REMOTE_DIR}/alertmanager/"

# Upload Grafana dashboards
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  monitoring/grafana/dashboards/*.json \
  "${SSH_USER}@${MONITORING_IP}:${REMOTE_DIR}/grafana/dashboards/"

# Upload Grafana provisioning
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  monitoring/grafana/provisioning/datasources/datasource.yml \
  "${SSH_USER}@${MONITORING_IP}:${REMOTE_DIR}/grafana/provisioning/datasources/"

scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
  monitoring/grafana/provisioning/dashboards/dashboard.yml \
  "${SSH_USER}@${MONITORING_IP}:${REMOTE_DIR}/grafana/provisioning/dashboards/"

# Restart monitoring stack
echo "==> Restarting monitoring stack..."
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${SSH_USER}@${MONITORING_IP}" \
  "cd ${REMOTE_DIR} && docker compose restart"

echo "==> Done. Grafana: http://${MONITORING_IP}:3000 | Prometheus: http://${MONITORING_IP}:9090"
