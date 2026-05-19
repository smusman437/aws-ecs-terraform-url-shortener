#!/usr/bin/env bash
# =============================================================================
# redeploy-app.sh — App code only (no Terraform)
#
# Use when you changed app.py, Dockerfile, or requirements.txt
# and infrastructure (infra/*.tf) did NOT change.
#
# Usage:
#   export AWS_PROFILE=terraform-user
#   ./scripts/redeploy-app.sh          # default: dev label in logs
#   ./scripts/redeploy-app.sh prod     # same ECS cluster; use after deploy.sh prod
#
# Steps:
#   1. Build + push Docker image to ECR
#   2. Force ECS to pull :latest and restart tasks
#   3. Wait until /health is OK
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_env "${1:-dev}"

require_cmd docker aws curl
check_aws_profile
check_terraform

# ECS must already exist (run ./scripts/deploy.sh first)
if ! aws ecs describe-services \
  --cluster url-shortener-cluster \
  --services url-shortener-service \
  --region "$AWS_REGION" \
  --query 'services[0].status' --output text 2>/dev/null | grep -q ACTIVE; then
  die "ECS service not found. Run ./scripts/deploy.sh ${ENV} first."
fi

echo ""
echo "=============================================="
echo "  Redeploy APP only (${ENV})"
echo "  No Terraform — image + ECS rollout only"
echo "=============================================="
echo ""

log "Step 1/3 — Build and push Docker image to ECR"
cd "$ROOT_DIR"
"${SCRIPT_DIR}/deploy-image.sh"

log "Step 2/3 — Force ECS to deploy new image"
aws ecs update-service \
  --cluster url-shortener-cluster \
  --service url-shortener-service \
  --force-new-deployment \
  --region "$AWS_REGION" \
  --no-cli-pager \
  --output text >/dev/null

log "Step 3/3 — Wait until service is healthy"
wait_for_ecs_healthy 360

API_URL=$(get_api_url)
echo ""
echo "=============================================="
echo "  App redeploy complete (${ENV})"
echo "  API URL: ${API_URL}"
echo "=============================================="
echo ""
echo "Test:  ./scripts/test-api.sh"
echo ""
