#!/usr/bin/env bash
# =============================================================================
# plan.sh — Preview Terraform changes WITHOUT applying (safe review)
#
# Usage:
#   export AWS_PROFILE=terraform-user
#   ./scripts/plan.sh dev
#   ./scripts/plan.sh prod
#
# Shows what terraform apply would create, change, or destroy.
# Does not modify AWS. After review, run ./scripts/deploy.sh to apply.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

resolve_env "${1:-dev}"

require_cmd terraform
check_aws_profile
check_terraform

ensure_tfvars
terraform_init

echo ""
echo "=============================================="
echo "  Terraform PLAN only (${ENV})"
echo "  File: infra/${TFVARS}"
echo "  No AWS changes will be made"
echo "=============================================="
echo ""

terraform_plan_only

echo "Next steps:"
echo "  Apply:    ./scripts/deploy.sh ${ENV}"
echo "  Destroy:  ./scripts/destroy.sh ${ENV}"
echo ""
