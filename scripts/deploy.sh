#!/usr/bin/env bash
# deploy.sh — Deploy a new version via ASG instance refresh
# Usage: ./scripts/deploy.sh [image-tag]
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-north-1}"
PROJECT_NAME="${PROJECT_NAME:-fullstack-deploy}"
IMAGE_TAG="${1:-latest}"

echo "==> Deploying image tag: ${IMAGE_TAG}"

# Find the ASG
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region "${AWS_REGION}" \
  --query "AutoScalingGroups[?contains(Tags[?Key=='Name'].Value | [0], '${PROJECT_NAME}')].AutoScalingGroupName | [0]" \
  --output text)

if [ "${ASG_NAME}" = "None" ] || [ -z "${ASG_NAME}" ]; then
  echo "ERROR: Could not find ASG for project ${PROJECT_NAME}"
  exit 1
fi

echo "==> Found ASG: ${ASG_NAME}"

# Trigger instance refresh
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --region "${AWS_REGION}" \
  --auto-scaling-group-name "${ASG_NAME}" \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 120}' \
  --query "InstanceRefreshId" \
  --output text)

echo "==> Instance refresh started: ${REFRESH_ID}"

# Wait for completion
echo "==> Waiting for instance refresh to complete..."
for i in {1..40}; do
  STATUS=$(aws autoscaling describe-instance-refreshes \
    --region "${AWS_REGION}" \
    --auto-scaling-group-name "${ASG_NAME}" \
    --instance-refresh-ids "${REFRESH_ID}" \
    --query "InstanceRefreshes[0].Status" \
    --output text)

  echo "    Status: ${STATUS} (attempt ${i}/40)"

  case "${STATUS}" in
    Successful)
      echo "==> Deployment completed successfully!"
      exit 0
      ;;
    Failed|Cancelled)
      echo "ERROR: Instance refresh ${STATUS}"
      exit 1
      ;;
  esac

  sleep 15
done

echo "ERROR: Timed out waiting for instance refresh"
exit 1
