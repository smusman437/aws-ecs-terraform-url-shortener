#!/usr/bin/env bash
# =============================================================================
# deploy-image.sh — Build Docker image and push to AWS ECR only
# (Does NOT run Terraform or update ECS — use deploy.sh for full deploy)
#
# Usage:
#   export AWS_PROFILE=terraform-user
#   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#   ./scripts/deploy-image.sh
# =============================================================================

set -euo pipefail

# No pager pause on AWS CLI output (see scripts/lib/common.sh)
export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=off

# Fail if AWS_ACCOUNT_ID is not set; show helpful message
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID (aws sts get-caller-identity --query Account --output text)}"
# Default region if not exported
: "${AWS_REGION:=us-east-1}"

# Full image URL in your private ECR registry
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/url-shortener"

echo "Logging in to ECR..."
# AWS returns a temporary password; pipe it to docker login
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin \
  "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Building image (linux/arm64 for ECS Fargate ARM64)..."
# Must match ECS task runtime_platform (ARM64) or you get "exec format error"
docker build --platform linux/arm64 -t url-shortener .

echo "Tagging and pushing..."
# Tag local image with ECR URL so docker push knows the destination
docker tag url-shortener:latest "${ECR_URI}:latest"
# Upload layers to ECR; ECS pulls :latest on next deployment
docker push "${ECR_URI}:latest"

echo "Done. Image pushed to ${ECR_URI}:latest"
