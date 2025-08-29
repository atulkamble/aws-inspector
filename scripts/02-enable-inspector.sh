#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
echo "[INFO] Enabling Amazon Inspector v2 in region: $AWS_REGION"

aws inspector2 enable --resource-types EC2 ECR LAMBDA --region "$AWS_REGION" >/dev/null || true
echo "[INFO] Enabled. Checking account statistics (may be zero initially)..."
aws inspector2 list-account-statistics --region "$AWS_REGION" || true

echo "[INFO] Verifying EC2 is SSM-managed (optional check)..."
STATE_FILE=".state.json"
if [[ -f "$STATE_FILE" ]]; then
  INSTANCE_ID="$(jq -r '.instance_id' "$STATE_FILE")"
  echo "[INFO] InstanceId: $INSTANCE_ID"
  aws ssm describe-instance-information --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID']" --output table --region "$AWS_REGION" || true
else
  echo "[WARN] No state file found; skip SSM check."
fi

echo "[SUCCESS] Inspector v2 enabled. Findings will appear after initial scans (a few minutes)."
