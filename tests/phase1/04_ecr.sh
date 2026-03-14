#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 04: ECR
#
# Verifies:
#   - Repository exists
#   - Image scanning on push is enabled
#   - At least one tagged image is present
#   - 'latest' tag exists
#   - Lifecycle policy is configured
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "04 · ECR"

# ── 1. Repository exists ──────────────────────────────────────────────────────
info "Checking ECR repository: ${ECR_REPO_NAME}"
REPO=$(aws ecr describe-repositories \
  --repository-names "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --query "repositories[0]" \
  --output json 2>/dev/null || echo "{}")

REPO_URI=$(echo "$REPO" | jq -r '.repositoryUri // ""')
SCAN_ON_PUSH=$(echo "$REPO" | jq -r '.imageScanningConfiguration.scanOnPush // false')
ENCRYPTION=$(echo "$REPO" | jq -r '.encryptionConfiguration.encryptionType // "NONE"')

if [[ -n "$REPO_URI" && "$REPO_URI" != "null" ]]; then
  pass "Repository '${ECR_REPO_NAME}' exists: $REPO_URI"
else
  fail "Repository '${ECR_REPO_NAME}' not found in region ${AWS_REGION}."
  summarize "ECR"
  exit $?
fi

# ── 2. Scan on push ───────────────────────────────────────────────────────────
if [[ "$SCAN_ON_PUSH" == "true" ]]; then
  pass "Image scanning on push is enabled."
else
  warn "Image scanning on push is disabled — enable it for security best practices."
fi

# ── 3. Encryption ─────────────────────────────────────────────────────────────
if [[ "$ENCRYPTION" == "AES256" || "$ENCRYPTION" == "KMS" ]]; then
  pass "Repository encryption: $ENCRYPTION"
else
  warn "Repository encryption is '${ENCRYPTION}'."
fi

# ── 4. Tagged images ──────────────────────────────────────────────────────────
TAGGED_IMAGES=$(aws ecr list-images \
  --repository-name "$ECR_REPO_NAME" \
  --filter tagStatus=TAGGED \
  --region "$AWS_REGION" \
  --query "imageIds" \
  --output json 2>/dev/null || echo "[]")

TAGGED_COUNT=$(echo "$TAGGED_IMAGES" | jq 'length')
if [[ "$TAGGED_COUNT" -gt 0 ]]; then
  pass "$TAGGED_COUNT tagged image(s) found in repository."
else
  warn "No tagged images found — container has not been built and pushed yet."
fi

# ── 5. 'latest' tag ───────────────────────────────────────────────────────────
LATEST=$(aws ecr describe-images \
  --repository-name "$ECR_REPO_NAME" \
  --image-ids imageTag=latest \
  --region "$AWS_REGION" \
  --query "imageDetails[0]" \
  --output json 2>/dev/null || echo "{}")

LATEST_PUSHED=$(echo "$LATEST" | jq -r '.imagePushedAt // ""')
if [[ -n "$LATEST_PUSHED" && "$LATEST_PUSHED" != "null" ]]; then
  pass "'latest' tag found (pushed: $LATEST_PUSHED)."
  DIGEST=$(echo "$LATEST" | jq -r '.imageDigest // ""')
  info "Image digest: ${DIGEST:0:32}…"

  # Scan findings for the latest image
  SCAN_STATUS=$(echo "$LATEST" | jq -r '.imageScanStatus.status // "UNSUPPORTED"')
  CRITICAL=$(echo "$LATEST" | jq -r '.imageScanFindingsSummary.findingSeverityCounts.CRITICAL // 0')
  HIGH=$(echo "$LATEST" | jq -r '.imageScanFindingsSummary.findingSeverityCounts.HIGH // 0')

  if [[ "$SCAN_STATUS" == "COMPLETE" ]]; then
    if [[ "$CRITICAL" -gt 0 ]]; then
      fail "Latest image has $CRITICAL CRITICAL vulnerability finding(s) — review ECR scan results."
    elif [[ "$HIGH" -gt 0 ]]; then
      warn "Latest image has $HIGH HIGH severity finding(s)."
    else
      pass "No CRITICAL/HIGH scan findings on latest image."
    fi
  elif [[ "$SCAN_STATUS" == "IN_PROGRESS" ]]; then
    info "Image scan is IN_PROGRESS."
  else
    info "Scan status: $SCAN_STATUS."
  fi
else
  warn "'latest' tag not found — the CI/CD pipeline may not have run yet."
fi

# ── 6. Lifecycle policy ────────────────────────────────────────────────────────
LIFECYCLE=$(aws ecr get-lifecycle-policy \
  --repository-name "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --query "lifecyclePolicyText" \
  --output text 2>/dev/null || echo "NONE")

if [[ "$LIFECYCLE" != "NONE" && -n "$LIFECYCLE" ]]; then
  pass "Lifecycle policy is configured."
else
  warn "No lifecycle policy found — old images will accumulate and incur storage costs."
fi

summarize "ECR"
