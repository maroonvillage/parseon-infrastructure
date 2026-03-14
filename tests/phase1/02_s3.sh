#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 02: S3 Buckets
#
# Verifies both S3 buckets:
#   - Documents bucket  (parseon-dev-bucket)
#   - Frontend bucket   (parseon-dev-frontend)
#
# Checks per bucket:
#   - Bucket exists
#   - Public access block enforced
#   - Server-side encryption enabled
#   - Versioning status
#   - Frontend bucket: at least one object present (index.html)
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "02 · S3 Buckets"

check_bucket_exists() {
  local bucket="$1"
  aws s3api head-bucket --bucket "$bucket" --region "$AWS_REGION" 2>/dev/null
}

check_public_access_block() {
  local bucket="$1"
  local config
  config=$(aws s3api get-public-access-block --bucket "$bucket" \
    --query "PublicAccessBlockConfiguration" --output json 2>/dev/null || echo "{}")
  local blocked
  blocked=$(echo "$config" | jq -r '
    if .BlockPublicAcls == true and
       .IgnorePublicAcls == true and
       .BlockPublicPolicy == true and
       .RestrictPublicBuckets == true
    then "yes" else "no" end' 2>/dev/null || echo "no")
  echo "$blocked"
}

check_encryption() {
  local bucket="$1"
  aws s3api get-bucket-encryption --bucket "$bucket" \
    --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" \
    --output text 2>/dev/null || echo "NONE"
}

check_versioning() {
  local bucket="$1"
  aws s3api get-bucket-versioning --bucket "$bucket" \
    --query "Status" --output text 2>/dev/null || echo "None"
}

# ── Helper: run all checks for a given bucket ──────────────────────────────────
verify_bucket() {
  local bucket="$1"
  local label="$2"
  local expect_versioning="${3:-false}"
  local check_objects="${4:-false}"

  echo ""
  info "Bucket: $bucket ($label)"

  if check_bucket_exists "$bucket"; then
    pass "Bucket exists."
  else
    fail "Bucket '${bucket}' not found or not accessible."
    return
  fi

  local pab
  pab=$(check_public_access_block "$bucket")
  if [[ "$pab" == "yes" ]]; then
    pass "Public access block is fully enforced."
  else
    fail "Public access block is NOT fully enforced — bucket may be publicly accessible."
  fi

  local sse
  sse=$(check_encryption "$bucket")
  if [[ "$sse" == "AES256" || "$sse" == "aws:kms" ]]; then
    pass "Server-side encryption enabled: $sse"
  else
    fail "Server-side encryption is NOT enabled (got: $sse)."
  fi

  local versioning
  versioning=$(check_versioning "$bucket")
  if [[ "$expect_versioning" == "true" ]]; then
    if [[ "$versioning" == "Enabled" ]]; then
      pass "Versioning is Enabled."
    else
      fail "Versioning is not Enabled (got: $versioning) — required for this bucket."
    fi
  else
    info "Versioning: $versioning"
  fi

  if [[ "$check_objects" == "true" ]]; then
    local count
    count=$(aws s3 ls "s3://${bucket}/" --recursive --region "$AWS_REGION" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      pass "Frontend bucket contains $count object(s) — frontend assets deployed."
      # Specifically look for index.html
      local has_index
      has_index=$(aws s3 ls "s3://${bucket}/index.html" --region "$AWS_REGION" 2>/dev/null || true)
      if [[ -n "$has_index" ]]; then
        pass "index.html is present in frontend bucket."
      else
        warn "index.html not found at bucket root — React app may not be deployed yet."
      fi
    else
      warn "Frontend bucket is empty — static assets have not been deployed yet."
    fi
  fi
}

# ── Document storage bucket ────────────────────────────────────────────────────
verify_bucket "$S3_DOC_BUCKET"     "Document Storage"    "false" "false"

# ── Frontend (React) bucket ────────────────────────────────────────────────────
verify_bucket "$S3_FRONTEND_BUCKET" "React Frontend"      "true"  "true"

summarize "S3"
