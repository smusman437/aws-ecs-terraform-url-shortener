#!/usr/bin/env bash
# =============================================================================
# test-api.sh — Test /health, /shorten, redirect, /all
#
# Usage:
#   ./scripts/test-api.sh                        # auto: live ALB or localhost
#   ./scripts/test-api.sh http://localhost:8080  # force local
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Optional first argument: base URL to test
BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  # Try Terraform output first (= live AWS URL)
  if BASE_URL=$(get_api_url 2>/dev/null) && [[ -n "$BASE_URL" ]]; then
    log "Testing LIVE API: ${BASE_URL}"
  else
    # No Terraform state / not deployed → assume local Docker
    BASE_URL="http://localhost:8080"
    log "Testing LOCAL API: ${BASE_URL}"
  fi
fi
# Remove trailing slash so we can append /health cleanly
BASE_URL="${BASE_URL%/}"

pass() { echo "  OK  $*"; }
fail() { echo "  FAIL $*" >&2; exit 1; }

# --- Test 1: GET /health (ALB uses this for health checks) ---
log "1. Health check"
resp=$(curl -sf "${BASE_URL}/health") || fail "GET /health"
echo "      ${resp}"
[[ "$resp" == *"ok"* ]] && pass "/health"

# --- Test 2: POST /shorten — create a short code ---
log "2. Shorten URL"
resp=$(curl -sf -X POST "${BASE_URL}/shorten" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.google.com"}') || fail "POST /shorten"
echo "      ${resp}"
# Extract short_code from JSON using Python (installed on Mac by default)
CODE=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['short_code'])" 2>/dev/null) \
  || die "Could not parse short_code from response"
pass "short_code=${CODE}"

# --- Test 3: GET /{code} — should redirect to Google ---
log "3. Redirect"
# -L = follow redirects; -w = print final HTTP status code
status=$(curl -s -o /dev/null -w "%{http_code}" -L "${BASE_URL}/${CODE}") || fail "GET /${CODE}"
[[ "$status" == "200" ]] && pass "redirect HTTP ${status}" || fail "redirect HTTP ${status}"

# --- Test 4: GET /all — debug endpoint listing all URLs ---
log "4. List all (debug endpoint)"
curl -sf "${BASE_URL}/all" >/dev/null && pass "GET /all"

log "5. Swagger UI reachable"
if curl -sf "${BASE_URL}/apidocs" >/dev/null 2>&1; then
  pass "GET /apidocs (open in browser to test interactively)"
else
  warn "Swagger UI not reachable at ${BASE_URL}/apidocs"
fi

echo ""
echo "All tests passed for ${BASE_URL}"
echo "Swagger UI: ${BASE_URL}/apidocs"
