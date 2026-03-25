#!/usr/bin/env bash
# rollback.sh — Roll back to the previous launch template version
# Usage: ./scripts/rollback.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-north-1}"
PROJECT_NAME="${PROJECT_NAME:-fullstack-deploy}"

echo "==> Starting rollback for ${PROJECT_NAME}"

# Find the ASG
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region "${AWS_REGION}" \
  --query "AutoScalingGroups[?contains(Tags[?Key=='Name'].Value | [0], '${PROJECT_NAME}')].AutoScalingGroupName | [0]" \
  --output text)

# Get launch template info
LT_ID=$(aws autoscaling describe-auto-scaling-groups \
  --region "${AWS_REGION}" \
  --auto-scaling-group-names "${ASG_NAME}" \
  --query "AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId" \
  --output text)

CURRENT_VERSION=$(aws autoscaling describe-auto-scaling-groups \
  --region "${AWS_REGION}" \
  --auto-scaling-group-names "${ASG_NAME}" \
  --query "AutoScalingGroups[0].LaunchTemplate.Version" \
  --output text)

echo "==> Current launch template version: ${CURRENT_VERSION}"

# Get the previous version number
PREVIOUS_VERSION=$(aws ec2 describe-launch-template-versions \
  --region "${AWS_REGION}" \
  --launch-template-id "${LT_ID}" \
  --query "LaunchTemplateVersions | sort_by(@, &VersionNumber) | [-2].VersionNumber" \
  --output text)

if [ "${PREVIOUS_VERSION}" = "None" ] || [ -z "${PREVIOUS_VERSION}" ]; then
  echo "ERROR: No previous version found to roll back to"
  exit 1
fi

echo "==> Rolling back to version: ${PREVIOUS_VERSION}"

# Update ASG to use the previous version
aws autoscaling update-auto-scaling-group \
  --region "${AWS_REGION}" \
  --auto-scaling-group-name "${ASG_NAME}" \
  --launch-template "LaunchTemplateId=${LT_ID},Version=${PREVIOUS_VERSION}"

# Trigger instance refresh
aws autoscaling start-instance-refresh \
  --region "${AWS_REGION}" \
  --auto-scaling-group-name "${ASG_NAME}" \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 120}'

echo "==> Rollback initiated. Monitor with:"
echo "    aws autoscaling describe-instance-refreshes --auto-scaling-group-name ${ASG_NAME}"
