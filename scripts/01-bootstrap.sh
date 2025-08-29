#!/usr/bin/env bash
set -euo pipefail

# Create IAM role/profile for SSM, security group, and an EC2 instance in the default VPC.
# Requires: aws, jq
# Optional env vars: AWS_REGION, INSTANCE_TYPE (default t3.micro), EC2_NAME, SG_NAME

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
EC2_NAME="${EC2_NAME:-inspector-demo-ec2}"
SG_NAME="${SG_NAME:-inspector-demo-sg}"
ROLE_NAME="${ROLE_NAME:-InspectorSSMRole}"
INSTANCE_PROFILE="${INSTANCE_PROFILE:-InspectorSSMInstanceProfile}"
STATE_FILE=".state.json"

echo "[INFO] Region: $AWS_REGION"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "[INFO] Account: $ACCOUNT_ID"

# Ensure jq exists
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required. Install jq and retry."; exit 1; }

# Get default VPC id
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "[ERROR] No default VPC found in $AWS_REGION. Provide VPC/SUBNET manually (script not configured for that)."
  exit 1
fi
echo "[INFO] Default VPC: $VPC_ID"

# Get a default subnet
SUBNET_ID="$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text)"
if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
  # fallback: any subnet in default VPC
  SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[0].SubnetId' --output text)"
fi
echo "[INFO] Subnet: $SUBNET_ID"

# Create/ensure IAM role for SSM
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[INFO] Creating IAM role $ROLE_NAME"
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE_NAME"     --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null
fi

# Create/ensure instance profile
if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE" >/dev/null 2>&1; then
  echo "[INFO] Creating instance profile $INSTANCE_PROFILE"
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE" --role-name "$ROLE_NAME" >/dev/null
fi

# Create/ensure security group
SG_ID="$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)"
if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  echo "[INFO] Creating security group $SG_NAME"
  SG_ID="$(aws ec2 create-security-group --group-name "$SG_NAME" --vpc-id "$VPC_ID" --description "Inspector demo SG" --query 'GroupId' --output text)"
  # Allow HTTP (80) from anywhere for demo purposes
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
  # Egress all
  aws ec2 authorize-security-group-egress --group-id "$SG_ID" --protocol -1 --port all --cidr 0.0.0.0/0 >/dev/null 2>/dev/null || true
fi
echo "[INFO] Security Group: $SG_ID"

# Get latest Amazon Linux 2023 AMI via SSM
AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
AMI_ID="$(aws ssm get-parameters --names "$AMI_PARAM" --query 'Parameters[0].Value' --output text --region "$AWS_REGION")"
if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  echo "[ERROR] Could not resolve AL2023 AMI via SSM parameter. Check region: $AWS_REGION"
  exit 1
fi
echo "[INFO] AMI: $AMI_ID"

# Launch EC2 instance
echo "[INFO] Launching EC2 instance ($INSTANCE_TYPE) ..."
USER_DATA=$(base64 <<'EOF'
#!/bin/bash
set -e
# Basic demo service and ensure SSM agent is running
(yum -y install httpd || dnf -y install httpd) || true
systemctl enable --now httpd || true
echo "Hello from Amazon Inspector demo" > /var/www/html/index.html
systemctl enable --now amazon-ssm-agent || true
EOF
)

RUN_JSON="$(aws ec2 run-instances   --image-id "$AMI_ID"   --instance-type "$INSTANCE_TYPE"   --iam-instance-profile Name="$INSTANCE_PROFILE"   --security-group-ids "$SG_ID"   --subnet-id "$SUBNET_ID"   --user-data "$USER_DATA"   --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2_NAME}]"   --query 'Instances[0]' --output json --region "$AWS_REGION")"

INSTANCE_ID="$(jq -r '.InstanceId' <<<"$RUN_JSON")"
echo "[INFO] InstanceId: $INSTANCE_ID"

echo "[INFO] Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

PUB_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$AWS_REGION")"
echo "[INFO] Public IP: $PUB_IP"

# Persist state
jq -n --arg instance_id "$INSTANCE_ID" --arg sg_id "$SG_ID" --arg role_name "$ROLE_NAME" --arg profile "$INSTANCE_PROFILE" --arg region "$AWS_REGION" '{
  instance_id: $instance_id,
  sg_id: $sg_id,
  role_name: $role_name,
  instance_profile: $profile,
  region: $region
}' > "$STATE_FILE"

echo "[SUCCESS] EC2 ready. Try: http://$PUB_IP"
