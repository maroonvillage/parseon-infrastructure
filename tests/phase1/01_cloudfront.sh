#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 01: CloudFront
#
# Verifies:
#   - Distribution exists and is enabled
#   - Correct origins configured (S3 frontend + ALB API)
#   - HTTP reachability (index.html returns 2xx/3xx)
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "01 · CloudFront"

# ── 1. List distributions and find parseon's ──────────────────────────────────
info "Fetching CloudFront distributions…"
DISTRIBUTIONS=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[*].{Id:Id,Domain:DomainName,Origins:Origins.Items[*].DomainName,Enabled:Enabled,Status:Status}" \
  --output json 2>/dev/null || echo "[]")

if [[ "$DISTRIBUTIONS" == "[]" || -z "$DISTRIBUTIONS" ]]; then
  fail "No CloudFront distributions found in this account."
  summarize "CloudFront"
  exit $?
fi

# Match by S3 frontend origin or known name prefix
DIST=$(echo "$DISTRIBUTIONS" | jq -r \
  --arg bucket "${S3_FRONTEND_BUCKET}" \
  '.[] | select(.Origins[] | contains($bucket)) | .' | head -c 4096)

if [[ -z "$DIST" ]]; then
  # Fall back: match any distribution whose domain was exported from Terraform
  if [[ -n "${CLOUDFRONT_DOMAIN:-}" ]]; then
    DIST=$(echo "$DISTRIBUTIONS" | jq -r \
      --arg domain "${CLOUDFRONT_DOMAIN}" \
      '.[] | select(.Domain == $domain) | .')
  fi
fi

if [[ -z "$DIST" ]]; then
  fail "Could not find a CloudFront distribution associated with bucket '${S3_FRONTEND_BUCKET}'."
  warn "Available distributions:"
  echo "$DISTRIBUTIONS" | jq -r '.[].Domain' | while read -r d; do info "  $d"; done
  summarize "CloudFront"
  exit $?
fi

DIST_ID=$(echo "$DIST" | jq -r '.Id')
DIST_DOMAIN=$(echo "$DIST" | jq -r '.Domain')
DIST_ENABLED=$(echo "$DIST" | jq -r '.Enabled')
DIST_STATUS=$(echo "$DIST" | jq -r '.Status')

info "Distribution ID  : $DIST_ID"
info "Domain           : $DIST_DOMAIN"

# ── 2. Enabled ────────────────────────────────────────────────────────────────
if [[ "$DIST_ENABLED" == "true" ]]; then
  pass "Distribution is enabled."
else
  fail "Distribution is DISABLED (Enabled=$DIST_ENABLED)."
fi

# ── 3. Deployed status ────────────────────────────────────────────────────────
if [[ "$DIST_STATUS" == "Deployed" ]]; then
  pass "Distribution status is Deployed."
else
  warn "Distribution status is '${DIST_STATUS}' (expected Deployed — may still be propagating)."
fi

# ── 4. Verify origins ─────────────────────────────────────────────────────────
DIST_DETAIL=$(aws cloudfront get-distribution --id "$DIST_ID" \
  --query "Distribution.DistributionConfig.Origins.Items[*].{Id:Id,Domain:DomainName}" \
  --output json 2>/dev/null || echo "[]")

S3_ORIGIN=$(echo "$DIST_DETAIL" | jq -r '.[].Domain' | grep -i "${S3_FRONTEND_BUCKET}" || true)
ALB_ORIGIN=$(echo "$DIST_DETAIL" | jq -r '.[].Domain' | grep -i "elb.amazonaws.com" || true)

if [[ -n "$S3_ORIGIN" ]]; then
  pass "S3 frontend origin present: $S3_ORIGIN"
else
  fail "S3 frontend origin not found (expected bucket: ${S3_FRONTEND_BUCKET})."
fi

if [[ -n "$ALB_ORIGIN" ]]; then
  pass "ALB API origin present: $ALB_ORIGIN"
else
  warn "ALB origin not found — API path caching may not be configured yet."
fi

# ── 5. HTTP reachability ──────────────────────────────────────────────────────
if command -v curl &>/dev/null; then
  CF_URL="${CLOUDFRONT_DOMAIN:-$DIST_DOMAIN}"
  info "Checking HTTP response for https://${CF_URL}/ …"
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 15 --location "https://${CF_URL}/" 2>/dev/null || echo "000")
  if [[ "$HTTP_STATUS" =~ ^(200|301|302|304)$ ]]; then
    pass "HTTPS GET https://${CF_URL}/ → HTTP $HTTP_STATUS"
  elif [[ "$HTTP_STATUS" == "403" ]]; then
    warn "HTTPS GET returned 403 — frontend assets may not be deployed to S3 yet."
  elif [[ "$HTTP_STATUS" == "000" ]]; then
    warn "Could not reach https://${CF_URL}/ (connection failed or timed out)."
  else
    fail "HTTPS GET https://${CF_URL}/ → unexpected HTTP $HTTP_STATUS"
  fi
else
  warn "curl not installed — skipping HTTP reachability check."
fi

summarize "CloudFront"
