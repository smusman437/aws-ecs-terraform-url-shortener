#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared helpers used by deploy.sh, destroy.sh, status.sh, etc.
# Do NOT run this file directly. Other scripts "source" it to reuse functions.
# =============================================================================

# Exit immediately on error, treat unset variables as errors, fail on pipe errors
set -euo pipefail

# Absolute path to project root (two levels up from scripts/lib/)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Where Terraform files live
INFRA_DIR="${ROOT_DIR}/infra"
# Use terraform-user profile unless you already exported AWS_PROFILE
AWS_PROFILE="${AWS_PROFILE:-terraform-user}"
# Default AWS region — must match infra/terraform.tfvars
AWS_REGION="${AWS_REGION:-us-east-1}"
# Child processes (aws CLI, terraform) inherit these
export AWS_PROFILE AWS_REGION

# Disable AWS CLI pager (less). Without this, JSON output pauses at "(END)"
# and waits for you to press 'q' before the script continues.
export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=off

# Print a green-style progress line
log()  { echo "==> $*"; }
# Print a warning to stderr (does not stop the script)
warn() { echo "WARNING: $*" >&2; }
# Print an error and exit with code 1
die()  { echo "ERROR: $*" >&2; exit 1; }

# Ensure commands like aws, docker, terraform exist before we use them
require_cmd() {
  local cmd  # loop variable for each command name
  for cmd in "$@"; do
    # command -v returns path if found; die if missing
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
  done
}

# Verify AWS CLI works and we are on the correct account
check_aws_profile() {
  require_cmd aws
  log "Using AWS profile: ${AWS_PROFILE}"

  local arn  # will hold identity ARN, e.g. arn:aws:iam::123:user/terraform-user
  # sts get-caller-identity = "who am I?" — fails if credentials are wrong
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) \
    || die "AWS CLI failed. Run: aws configure --profile ${AWS_PROFILE}"
  echo "    Identity: ${arn}"

  # Warn if you accidentally used expedient or another profile
  if [[ "$arn" != *"terraform-user"* ]] && [[ "${SKIP_PROFILE_CHECK:-}" != "1" ]]; then
    warn "Expected identity to contain 'terraform-user'. Set AWS_PROFILE=terraform-user"
  fi

  # 12-digit account ID — needed for ECR URL
  export AWS_ACCOUNT_ID
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  # Full ECR registry path where Docker images are stored in AWS
  export ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/url-shortener"
}

# Warn if Terraform is Intel-only on Apple Silicon (causes plugin timeouts)
check_terraform() {
  require_cmd terraform
  if ! terraform version 2>/dev/null | grep -q darwin_arm64; then
    if terraform version 2>/dev/null | grep -q darwin_amd64; then
      warn "Terraform is darwin_amd64 on an ARM Mac — install ARM Terraform to avoid plugin timeouts"
    fi
  fi
}

# After deploy, poll until ECS tasks are running AND /health returns 200 on the ALB
wait_for_ecs_healthy() {
  local cluster="url-shortener-cluster"   # ECS cluster name from Terraform
  local service="url-shortener-service" # ECS service name from Terraform
  local max_wait="${1:-300}"            # max seconds to wait (default 5 minutes)
  local elapsed=0                       # seconds waited so far

  log "Waiting for ECS service to be healthy (up to ${max_wait}s)..."
  while (( elapsed < max_wait )); do
    local running desired  # how many tasks run vs how many should run
    running=$(aws ecs describe-services \
      --cluster "$cluster" --services "$service" --region "$AWS_REGION" \
      --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
    desired=$(aws ecs describe-services \
      --cluster "$cluster" --services "$service" --region "$AWS_REGION" \
      --query 'services[0].desiredCount' --output text 2>/dev/null || echo "1")

    # All desired tasks running and at least one task up
    if [[ "$running" == "$desired" ]] && [[ "$running" != "0" ]]; then
      local alb_url
      alb_url=$(get_api_url 2>/dev/null || true)
      # curl -sf = silent, fail on HTTP errors — confirms ALB can reach the app
      if [[ -n "$alb_url" ]] && curl -sf "${alb_url}/health" >/dev/null 2>&1; then
        log "Service healthy (${running}/${desired} tasks, /health OK)"
        return 0  # success — exit function
      fi
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "    ... ${elapsed}s (running=${running}, desired=${desired})"
  done
  die "ECS service did not become healthy in time. Check: aws logs tail /ecs/url-shortener --follow"
}

# Read the public ALB URL from Terraform outputs (empty if infra not applied yet)
get_api_url() {
  (cd "$INFRA_DIR" && terraform output -raw api_url 2>/dev/null)
}

# Parse first argument as dev or prod; sets ENV and TFVARS
resolve_env() {
  ENV="${1:-dev}"
  case "$ENV" in
    dev)  TFVARS="terraform.tfvars" ;;
    prod) TFVARS="prod.tfvars" ;;
    *)
      die "Invalid environment '${ENV}'. Use: dev or prod"
      ;;
  esac
  export ENV TFVARS
}

# Ensure terraform.tfvars exists for dev (copy from example)
ensure_tfvars() {
  cd "$INFRA_DIR"
  if [[ "$TFVARS" == "terraform.tfvars" && ! -f "$TFVARS" ]]; then
    cp terraform.tfvars.example terraform.tfvars
    warn "Created terraform.tfvars from example"
  fi
  if [[ "$TFVARS" == "prod.tfvars" && ! -f "$TFVARS" ]]; then
    die "Missing prod.tfvars. Copy infra/prod.tfvars.example to infra/prod.tfvars"
  fi
}

# Run terraform init in infra/
terraform_init() {
  cd "$INFRA_DIR"
  terraform init -input=false
}

# Run terraform plan, then ask user to confirm before apply (unless AUTO_APPROVE=1)
# Usage: terraform_plan_review  →  plan only, always stops before apply
#        terraform_plan_confirm →  plan then prompt → apply on yes
terraform_plan_only() {
  cd "$INFRA_DIR"
  log "Terraform plan (${ENV}, -var-file=${TFVARS}) — review changes below"
  echo ""
  terraform plan -var-file="$TFVARS" -input=false
  echo ""
}

terraform_plan_confirm() {
  terraform_plan_only
  if [[ "${AUTO_APPROVE:-}" == "1" ]]; then
    log "AUTO_APPROVE=1 — applying plan..."
  else
    read -r -p "Apply the plan above? Type 'yes' to continue: " confirm
    [[ "$confirm" == "yes" ]] || die "Aborted (no changes applied)."
  fi
  # -auto-approve here: you already confirmed above (avoids Terraform asking twice)
  terraform apply -var-file="$TFVARS" -auto-approve -input=false
}
