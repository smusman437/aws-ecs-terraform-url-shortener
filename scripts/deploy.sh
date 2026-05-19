#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Full deploy: Terraform (plan → apply) + Docker + ECS
#
# Usage:
#   export AWS_PROFILE=terraform-user
#   ./scripts/deploy.sh dev
#   ./scripts/deploy.sh prod
#
# Steps:
#   1. terraform init
#   2. terraform plan + apply (review plan, type 'yes' to apply)
#   3. Build + push image to ECR
#   4. ECS force new deployment + wait for healthy
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_env "${1:-dev}"

require_cmd docker terraform curl
check_aws_profile
check_terraform

ensure_tfvars

echo ""
echo "=============================================="
echo "  Full deploy (${ENV})"
echo "  Terraform: infra/${TFVARS}"
if [[ "$ENV" == "prod" ]]; then
  echo "  Prod: 2 tasks, autoscaling 2–10 (see infra/prod.tfvars)"
fi
echo "=============================================="
echo ""

# --- Step 1–2: Terraform init, then plan (review) + apply (confirm) ---
log "Step 1/4 — Terraform init"
terraform_init

log "Step 2/4 — Terraform plan (review) + apply (you type 'yes')"
terraform_plan_confirm

# --- Step 3: Push app image ---
log "Step 3/4 — Build and push Docker image to ECR"
cd "$ROOT_DIR"
"${SCRIPT_DIR}/deploy-image.sh"

# --- Step 4: ECS rollout + health check ---
log "Step 4/4 — ECS deploy + wait for healthy"
aws ecs update-service \
  --cluster url-shortener-cluster \
  --service url-shortener-service \
  --force-new-deployment \
  --region "$AWS_REGION" \
  --no-cli-pager \
  --output text >/dev/null

wait_for_ecs_healthy 360

API_URL=$(get_api_url)
echo ""
echo "=============================================="
echo "  Deploy complete (${ENV})!"
echo "  API URL: ${API_URL}"
echo "=============================================="
echo ""
echo "App-only updates later:  ./scripts/redeploy-app.sh ${ENV}"
echo "Preview infra changes:   ./scripts/plan.sh ${ENV}"
echo "Test:                    ./scripts/test-api.sh"
echo ""
