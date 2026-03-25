#!/bin/bash
set -euo pipefail

# ── Install Docker & Docker Compose ──────────────────────────────
dnf update -y
dnf install -y docker git
systemctl enable docker
systemctl start docker

# Docker Compose v2 plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ── Create monitoring directory structure ────────────────────────
mkdir -p /opt/monitoring/{prometheus,grafana/{provisioning/{datasources,dashboards},dashboards},alertmanager}

# ── Prometheus config ────────────────────────────────────────────
cat > /opt/monitoring/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alerts.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]

  - job_name: app-instances
    ec2_sd_configs:
      - region: ${aws_region}
        port: 8000
        filters:
          - name: "tag:Name"
            values: ["${project_name}-${environment}-app"]
          - name: "instance-state-name"
            values: ["running"]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: "$${1}:8000"
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone

  - job_name: app-node-exporters
    ec2_sd_configs:
      - region: ${aws_region}
        port: 9100
        filters:
          - name: "tag:Name"
            values: ["${project_name}-${environment}-app"]
          - name: "instance-state-name"
            values: ["running"]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: "$${1}:9100"
EOF

# ── Prometheus alert rules ───────────────────────────────────────
cat > /opt/monitoring/prometheus/alerts.yml <<'EOF'
groups:
  - name: application
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status_code=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate (> 5%)"
          description: "Error rate is {{ $value | humanizePercentage }} on {{ $labels.instance }}"

      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1.0
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "High p95 latency (> 1s)"
          description: "p95 latency is {{ $value }}s on {{ $labels.instance }}"

      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is down"

  - name: infrastructure
    rules:
      - alert: HighCPU
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage (> 80%)"

      - alert: HighMemory
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage (> 85%)"

      - alert: DiskSpaceLow
        expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low (> 85% used)"
EOF

# ── AlertManager config ──────────────────────────────────────────
cat > /opt/monitoring/alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ["alertname", "severity"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: default

  routes:
    - match:
        severity: critical
      receiver: default
      repeat_interval: 1h

receivers:
  - name: default
    webhook_configs:
      - url: "http://localhost:9095/alert"
        send_resolved: true
EOF

# ── Grafana datasource provisioning ─────────────────────────────
cat > /opt/monitoring/grafana/provisioning/datasources/datasource.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

# ── Grafana dashboard provisioning ──────────────────────────────
cat > /opt/monitoring/grafana/provisioning/dashboards/dashboard.yml <<'EOF'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF

# ── Docker Compose for monitoring stack ──────────────────────────
cat > /opt/monitoring/docker-compose.yml <<'EOF'
services:
  prometheus:
    image: prom/prometheus:v2.51.0
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.retention.time=15d"
      - "--web.enable-lifecycle"

  grafana:
    image: grafana/grafana:10.4.0
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana_data:/var/lib/grafana

  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--path.rootfs=/rootfs"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"

volumes:
  prometheus_data:
  grafana_data:
EOF

# ── Start the monitoring stack ───────────────────────────────────
cd /opt/monitoring
docker compose up -d
