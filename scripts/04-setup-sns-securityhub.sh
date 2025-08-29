#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
TOPIC_NAME="${TOPIC_NAME:-InspectorAlerts}"
RULE_NAME="${RULE_NAME:-InspectorFindingsToSNS}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

echo "[INFO] Region: $AWS_REGION"

# 1) Create SNS Topic
echo "[INFO] Ensuring SNS topic $TOPIC_NAME ..."
TOPIC_ARN="$(aws sns create-topic --name "$TOPIC_NAME" --query TopicArn --output text --region "$AWS_REGION")"
echo "[INFO] SNS Topic: $TOPIC_ARN"

if [[ -n "$ALERT_EMAIL" ]]; then
  echo "[INFO] Subscribing $ALERT_EMAIL (confirm via email) ..."
  aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$ALERT_EMAIL" --region "$AWS_REGION" >/dev/null
fi

# 2) Enable Security Hub and import Inspector product
echo "[INFO] Enabling Security Hub (no-op if already enabled) ..."
aws securityhub enable-security-hub --region "$AWS_REGION" >/dev/null 2>&1 || true

PRODUCT_ARN="arn:aws:securityhub:$AWS_REGION::product/aws/inspector"
echo "[INFO] Importing findings for product: $PRODUCT_ARN"
aws securityhub enable-import-findings-for-product --product-arn "$PRODUCT_ARN" --region "$AWS_REGION" >/dev/null 2>&1 || true

# 3) Create EventBridge rule to route Security Hub findings to SNS
echo "[INFO] Creating/putting EventBridge rule $RULE_NAME ..."
EVENT_PATTERN='{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "ProductName": ["Inspector"]
    }
  }
}'
aws events put-rule --name "$RULE_NAME" --event-pattern "$EVENT_PATTERN" --region "$AWS_REGION" >/dev/null

# 4) Create an IAM role for EventBridge to publish to SNS
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_NAME="EventBridgeToSNSRole"
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[INFO] Creating IAM role $ROLE_NAME"
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "events.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' >/dev/null
  POLICY_DOC="$(cat <<POL
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sns:Publish",
    "Resource": "$TOPIC_ARN"
  }]
}
POL
)"
  aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name EventBridgeToSNSPublish --policy-document "$POLICY_DOC" >/dev/null
fi
ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"

# 5) Attach target
echo "[INFO] Attaching SNS target to rule ..."
aws events put-targets --rule "$RULE_NAME" --targets "Id"="1","Arn"="$TOPIC_ARN","RoleArn"="$ROLE_ARN" --region "$AWS_REGION" >/dev/null

echo "[SUCCESS] Alerts wired: Security Hub (Inspector findings) → EventBridge → SNS ($TOPIC_ARN)."
echo "         If you provided ALERT_EMAIL, please confirm the subscription from your inbox."
