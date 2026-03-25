#!/usr/bin/env bash
# health-check.sh — Check health of all components
# Usage: ./scripts/health-check.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-north-1}"
PROJECT_NAME="${PROJECT_NAME:-fullstack-deploy}"

PASS=0
FAIL=0

check() {
  local name="$1"
  local result="$2"
  if [ "$result" = "0" ]; then
    echo "  [OK]   ${name}"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] ${name}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Health Check: ${PROJECT_NAME} ==="
echo ""

# ── ALB ──────────────────────────────────────────────────────────
echo "-- ALB --"
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'app')].DNSName | [0]" \
  --output text 2>/dev/null || echo "None")

if [ "${ALB_DNS}" != "None" ] && [ -n "${ALB_DNS}" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}/health" --max-time 5 || echo "000")
  check "ALB endpoint (${ALB_DNS})" "$([ "${HTTP_CODE}" = "200" ] && echo 0 || echo 1)"
else
  check "ALB (not found)" "1"
fi

# ── Target Group ─────────────────────────────────────────────────
echo ""
echo "-- Target Group --"
TG_ARN=$(aws elbv2 describe-target-groups \
  --region "${AWS_REGION}" \
  --query "TargetGroups[?contains(TargetGroupName, 'app')].TargetGroupArn | [0]" \
  --output text 2>/dev/null || echo "None")

if [ "${TG_ARN}" != "None" ] && [ -n "${TG_ARN}" ]; then
  HEALTHY=$(aws elbv2 describe-target-health \
    --region "${AWS_REGION}" \
    --target-group-arn "${TG_ARN}" \
    --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'] | length(@)" \
    --output text)
  TOTAL=$(aws elbv2 describe-target-health \
    --region "${AWS_REGION}" \
    --target-group-arn "${TG_ARN}" \
    --query "TargetHealthDescriptions | length(@)" \
    --output text)
  check "Healthy targets: ${HEALTHY}/${TOTAL}" "$([ "${HEALTHY}" -ge 1 ] && echo 0 || echo 1)"
fi

# ── RDS ──────────────────────────────────────────────────────────
echo ""
echo "-- RDS --"
DB_STATUS=$(aws rds describe-db-instances \
  --region "${AWS_REGION}" \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT_NAME}')].DBInstanceStatus | [0]" \
  --output text 2>/dev/null || echo "None")
check "RDS status: ${DB_STATUS}" "$([ "${DB_STATUS}" = "available" ] && echo 0 || echo 1)"

# ── CloudWatch Alarms ────────────────────────────────────────────
echo ""
echo "-- CloudWatch Alarms --"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
  --region "${AWS_REGION}" \
  --state-value ALARM \
  --alarm-name-prefix "${PROJECT_NAME}" \
  --query "MetricAlarms | length(@)" \
  --output text 2>/dev/null || echo "0")
check "Active alarms: ${ALARM_COUNT}" "$([ "${ALARM_COUNT}" = "0" ] && echo 0 || echo 1)"

# ── Summary ──────────────────────────────────────────────────────
echo ""
echo "=== Summary: ${PASS} passed, ${FAIL} failed ==="
exit "${FAIL}"
