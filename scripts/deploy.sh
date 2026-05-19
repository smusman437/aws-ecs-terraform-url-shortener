#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Full production deploy in one command
#
# Usage:
#   export AWS_PROFILE=terraform-user
#   ./scripts/deploy.sh dev    # 1 task, no autoscaling
#   ./scripts/deploy.sh prod   # 2 tasks, autoscaling enabled
#
# Steps: Terraform apply → Docker push → ECS redeploy → wait for healthy
# =============================================================================

set -euo pipefail

# Directory containing this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Load shared functions (check_aws_profile, wait_for_ecs_healthy, etc.)
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# First argument: dev or prod (default dev)
ENV="${1:-dev}"
# Set AUTO_APPROVE=1 to skip typing "yes" for terraform apply
AUTO_APPROVE="${AUTO_APPROVE:-}"

# Pick which .tfvars file Terraform uses
case "$ENV" in
  dev)  TFVARS="terraform.tfvars" ;;  # desired_count = 1
  prod) TFVARS="prod.tfvars" ;;       # desired_count = 2, autoscaling on
  *)    die "Usage: ./scripts/deploy.sh [dev|prod]" ;;
esac

require_cmd docker terraform curl
check_aws_profile   # verify credentials + set AWS_ACCOUNT_ID, ECR_URI
check_terraform     # warn if wrong Terraform architecture

# --- Step 1: Create/update AWS infrastructure ---
log "Step 1/4 — Terraform apply (${ENV})"
cd "$INFRA_DIR"
# Create tfvars from example if missing (first-time setup)
if [[ ! -f "$TFVARS" ]]; then
  cp terraform.tfvars.example terraform.tfvars
  warn "Created terraform.tfvars from example — review it before production use"
fi
# Download AWS provider plugin if needed
terraform init -input=false
# Create VPC, ECS, ALB, ECR, etc.
if [[ "$AUTO_APPROVE" == "1" ]]; then
  terraform apply -var-file="$TFVARS" -auto-approve
else
  terraform apply -var-file="$TFVARS"  # you type "yes" here
fi

# --- Step 2: Push app code as Docker image to ECR ---
log "Step 2/4 — Build and push Docker image to ECR"
cd "$ROOT_DIR"
"${SCRIPT_DIR}/deploy-image.sh"

# --- Step 3: Tell ECS to pull the new image and restart tasks ---
log "Step 3/4 — Force ECS to deploy new image"
aws ecs update-service \
  --cluster url-shortener-cluster \
  --service url-shortener-service \
  --force-new-deployment \
  --region "$AWS_REGION" \
  --output text >/dev/null

# --- Step 4: Wait until ALB /health returns OK ---
log "Step 4/4 — Wait until service is healthy"
wait_for_ecs_healthy 360

API_URL=$(get_api_url)
echo ""
echo "=============================================="
echo "  Deploy complete!"
echo "  API URL: ${API_URL}"
echo "=============================================="
echo ""
echo "Run tests:  ./scripts/test-api.sh"
echo ""
