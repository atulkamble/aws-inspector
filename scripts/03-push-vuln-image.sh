#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
REPO_NAME="${REPO_NAME:-inspector-demo}"
IMAGE_TAG="${IMAGE_TAG:-vuln}"
SRC_IMAGE="${SRC_IMAGE:-bkimminich/juice-shop:latest}"

echo "[INFO] Region: $AWS_REGION"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "[INFO] Account: $ACCOUNT_ID"

REPO_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME"

echo "[INFO] Ensuring ECR repo: $REPO_NAME"
aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1 ||   aws ecr create-repository --repository-name "$REPO_NAME" --image-scanning-configuration scanOnPush=true --region "$AWS_REGION" >/dev/null

echo "[INFO] Logging in to ECR ..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "[INFO] Pulling source image: $SRC_IMAGE"
docker pull "$SRC_IMAGE"

echo "[INFO] Tagging and pushing to ECR: $REPO_URI:$IMAGE_TAG"
docker tag "$SRC_IMAGE" "$REPO_URI:$IMAGE_TAG"
docker push "$REPO_URI:$IMAGE_TAG"

echo "[SUCCESS] Image pushed. Inspector will scan it automatically (allow a few minutes)."
