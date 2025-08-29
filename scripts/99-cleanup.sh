#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
STATE_FILE=".state.json"

ROLE_NAME="${ROLE_NAME:-InspectorSSMRole}"
INSTANCE_PROFILE="${INSTANCE_PROFILE:-InspectorSSMInstanceProfile}"
SG_NAME="${SG_NAME:-inspector-demo-sg}"
REPO_NAME="${REPO_NAME:-inspector-demo}"
RULE_NAME="${RULE_NAME:-InspectorFindingsToSNS}"
TOPIC_NAME="${TOPIC_NAME:-InspectorAlerts}"
EVENTS_ROLE="EventBridgeToSNSRole"

echo "[INFO] Region: $AWS_REGION"

# Terminate EC2
if [[ -f "$STATE_FILE" ]]; then
  INSTANCE_ID="$(jq -r '.instance_id' "$STATE_FILE")"
  SG_ID="$(jq -r '.sg_id' "$STATE_FILE")"
  echo "[INFO] Terminating instance $INSTANCE_ID ..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" >/dev/null || true
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true

  echo "[INFO] Deleting security group $SG_ID ..."
  aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" >/dev/null 2>&1 ||   aws ec2 delete-security-group --group-name "$SG_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || true
fi

# Delete ECR repo (force)
echo "[INFO] Deleting ECR repo $REPO_NAME (force) ..."
aws ecr delete-repository --repository-name "$REPO_NAME" --force --region "$AWS_REGION" >/dev/null 2>&1 || true

# Remove EventBridge targets and rule
echo "[INFO] Removing EventBridge targets/rule ..."
aws events remove-targets --rule "$RULE_NAME" --ids "1" --region "$AWS_REGION" >/dev/null 2>&1 || true
aws events delete-rule --name "$RULE_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || true

# Delete IAM role for EventBridge->SNS
echo "[INFO] Deleting IAM role $EVENTS_ROLE ..."
aws iam delete-role-policy --role-name "$EVENTS_ROLE" --policy-name EventBridgeToSNSPublish >/dev/null 2>&1 || true
aws iam delete-role --role-name "$EVENTS_ROLE" >/dev/null 2>&1 || true

# Delete SNS topic
echo "[INFO] Deleting SNS topic $TOPIC_NAME ..."
TOPIC_ARN="$(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':$TOPIC_NAME')].TopicArn" --output text --region "$AWS_REGION" || true)"
if [[ -n "$TOPIC_ARN" ]]; then
  # Unsubscribe all (best effort)
  SUBS="$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].SubscriptionArn' --output text --region "$AWS_REGION" || true)"
  for s in $SUBS; do
    if [[ "$s" != "PendingConfirmation" ]]; then
      aws sns unsubscribe --subscription-arn "$s" --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi
  done
  aws sns delete-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" >/dev/null 2>&1 || true
fi

# Delete IAM instance profile/role
echo "[INFO] Deleting instance profile $INSTANCE_PROFILE and role $ROLE_NAME ..."
aws iam remove-role-from-instance-profile --instance-profile-name "$INSTANCE_PROFILE" --role-name "$ROLE_NAME" >/dev/null 2>&1 || true
aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE" >/dev/null 2>&1 || true
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1 || true
aws iam delete-role --role-name "$ROLE_NAME" >/dev/null 2>&1 || true

# Optionally disable Inspector and Security Hub if NUKE=1
if [[ "${NUKE:-0}" == "1" ]]; then
  echo "[INFO] Disabling Inspector2 (EC2/ECR/LAMBDA) ..."
  aws inspector2 disable --resource-types EC2 ECR LAMBDA --region "$AWS_REGION" >/dev/null 2>&1 || true

  echo "[INFO] Disabling Security Hub ..."
  aws securityhub disable-security-hub --region "$AWS_REGION" >/dev/null 2>&1 || true
else
  echo "[INFO] Keeping Inspector/Security Hub (set NUKE=1 to disable)."
fi

# Remove state
rm -f "$STATE_FILE" || true

echo "[SUCCESS] Cleanup complete."
