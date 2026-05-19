#!/usr/bin/env bash
# =============================================================================
# status.sh — Check if your live deployment is healthy
# Usage: export AWS_PROFILE=terraform-user && ./scripts/status.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

check_aws_profile

# --- ECS: how many tasks are running vs desired ---
log "ECS service"
aws ecs describe-services \
  --cluster url-shortener-cluster \
  --services url-shortener-service \
  --region "$AWS_REGION" \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount,pending:pendingCount}' \
  --output table

# --- ALB: is the load balancer sending traffic to healthy containers? ---
log "ALB target health"
# Look up target group ARN by name (created by Terraform)
TG=$(aws elbv2 describe-target-groups --names url-shortener-tg --region "$AWS_REGION" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
if [[ -n "$TG" && "$TG" != "None" ]]; then
  # States: healthy, unhealthy, draining, initial
  aws elbv2 describe-target-health --target-group-arn "$TG" --region "$AWS_REGION" \
    --query 'TargetHealthDescriptions[*].{ip:Target.Id,state:TargetHealth.State}' \
    --output table
fi

# --- Public URL from Terraform + quick health ping ---
API_URL=$(get_api_url 2>/dev/null || echo "")
if [[ -n "$API_URL" ]]; then
  log "API URL: ${API_URL}"
  if curl -sf "${API_URL}/health" >/dev/null 2>&1; then
    echo "  /health: OK"
  else
    echo "  /health: not responding yet"
  fi
fi

# --- Last few ECS events (task started, failed, registered with ALB, etc.) ---
log "Recent ECS events"
aws ecs describe-services \
  --cluster url-shortener-cluster \
  --services url-shortener-service \
  --region "$AWS_REGION" \
  --query 'services[0].events[0:3].[createdAt,message]' \
  --output table
