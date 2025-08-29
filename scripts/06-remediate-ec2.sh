#!/usr/bin/env bash
set -euo pipefail

STATE_FILE=".state.json"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[ERROR] State file not found. Run scripts/01-bootstrap.sh first."
  exit 1
fi

INSTANCE_ID="$(jq -r '.instance_id' "$STATE_FILE")"
echo "[INFO] Remediating EC2 instance via SSM: $INSTANCE_ID (region: $AWS_REGION)"

CMD_ID="$(aws ssm send-command   --document-name 'AWS-RunShellScript'   --parameters commands='sudo dnf -y update || sudo yum -y update'   --targets "Key=InstanceIds,Values=$INSTANCE_ID"   --query 'Command.CommandId' --output text --region "$AWS_REGION")"

echo "[INFO] CommandId: $CMD_ID"
echo "[INFO] Waiting for command to complete..."
aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region "$AWS_REGION"

echo "[INFO] Fetching command output:"
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region "$AWS_REGION" --query '{Status:Status, Stdout:StandardOutputContent, Stderr:StandardErrorContent}' --output json

echo "[SUCCESS] EC2 patched. Inspector will refresh findings shortly."
