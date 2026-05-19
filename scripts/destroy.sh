#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Delete ALL AWS resources for this project
#
# Usage:
#   export AWS_PROFILE=terraform-user
#   ./scripts/destroy.sh dev
#   ./scripts/destroy.sh prod
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_env "${1:-dev}"

check_aws_profile
check_terraform

echo ""
echo "=============================================="
echo "  DESTROY all Terraform-managed AWS resources"
echo "  Environment: ${ENV}  (-var-file=${TFVARS})"
echo "  Profile:     ${AWS_PROFILE}"
echo "  Account:     ${AWS_ACCOUNT_ID}"
echo "=============================================="
echo ""
echo "Automated steps:"
echo "  1. aws ecr delete-repository --force"
echo "  2. terraform state rm aws_ecr_repository.url_shortener"
echo "  3. terraform destroy -var-file=${TFVARS}"
echo ""
read -r -p "Type 'destroy' to confirm: " confirm
[[ "$confirm" == "destroy" ]] || die "Aborted."

cd "$INFRA_DIR"
terraform init -input=false

# --- Step 1: Delete ECR repo + all Docker images in AWS ---
# Why: terraform destroy fails with "RepositoryNotEmptyException" if images exist
log "Step 1/3 — aws ecr delete-repository --force ..."
echo "  $ aws ecr delete-repository --repository-name url-shortener --force --region ${AWS_REGION}"
# --no-cli-pager = never open "less" (no "(END)" wait for a keypress)
# --output text  = short message instead of large JSON blob
if aws ecr delete-repository \
  --repository-name url-shortener \
  --force \
  --region "$AWS_REGION" \
  --no-cli-pager \
  --output text 2>/dev/null; then
  log "  ECR repository and all images deleted"
else
  log "  ECR not found (already deleted) — continuing"
fi

# --- Step 2: Remove ECR from Terraform state file ---
# Why: AWS no longer has the repo, but state still lists it → destroy gets confused
log "Step 2/3 — terraform state rm aws_ecr_repository.url_shortener ..."
if terraform state list 2>/dev/null | grep -q '^aws_ecr_repository\.url_shortener$'; then
  echo "  $ terraform state rm aws_ecr_repository.url_shortener"
  terraform state rm aws_ecr_repository.url_shortener
  log "  ECR removed from state"
else
  log "  ECR not in state (already removed) — continuing"
fi

# --- Step 3: Delete VPC, ECS, ALB, IAM, security groups, logs ---
log "Step 3/3 — terraform destroy -var-file=${TFVARS} ..."
echo "  $ terraform destroy -var-file=${TFVARS}"
if [[ "${AUTO_APPROVE:-}" == "1" ]]; then
  terraform destroy -var-file="$TFVARS" -auto-approve
else
  terraform destroy -var-file="$TFVARS"  # you type "yes" here
fi

echo ""
log "Destroy complete."
echo ""
echo "If you saw:"
echo '  "No changes. No objects need to be destroyed."'
echo '  "Resources: 0 destroyed."'
echo "  → That is SUCCESS. AWS is already clean."
echo ""
echo "Not removed (by design):"
echo "  - Local Docker image:  docker rmi url-shortener"
echo "  - IAM user terraform-user (delete in AWS Console if needed)"
