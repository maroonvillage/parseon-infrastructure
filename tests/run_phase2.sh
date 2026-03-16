#!/usr/bin/env bash
# =============================================================================
# Phase 2: Application Smoke Tests — Orchestrator
#
# Runs all API smoke tests against the deployed environment, after Phase 1
# infrastructure checks have passed.
#
# Usage:
#   ./tests/run_phase2.sh [dev|prod]
#
# Prerequisites:
#   TEST_USERNAME=<api user>  (required)
#   TEST_PASSWORD=<password>  (required — never hard-coded)
#   AWS CLI authenticated (for S3 object verification in 03_upload)
#   jq installed
#
# Options:
#   ENVIRONMENT=prod ./tests/run_phase2.sh
#   ./tests/run_phase2.sh prod
#
# Notes:
#   - API_BASE_URL is resolved from Terraform output alb_dns_name by default.
#     Override with: API_BASE_URL=http://my-alb-dns ./tests/run_phase2.sh
#   - Scripts run sequentially; 03_upload and 04_process depend on tokens
#     written by earlier scripts to TMPDIR.  05_golden_workflow is self-contained.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Allow environment override via positional arg
if [[ "${1:-}" != "" ]]; then
  export ENVIRONMENT="$1"
fi

source "$SCRIPT_DIR/config.sh"

# ── Credential check ──────────────────────────────────────────────────────────
if [[ -z "${TEST_USERNAME:-}" || -z "${TEST_PASSWORD:-}" ]]; then
  echo -e "${RED}✖ ERROR${NC}  TEST_USERNAME and TEST_PASSWORD must be set before running Phase 2."
  echo ""
  echo "  export TEST_USERNAME=smoketest"
  echo "  export TEST_PASSWORD=your_password"
  echo ""
  exit 1
fi

# ── Resolve API_BASE_URL from Terraform outputs (if not already set) ──────────
if [[ -z "${API_BASE_URL:-}" ]]; then
  TF_ENV_DIR="$SCRIPT_DIR/../environments/${ENVIRONMENT}"
  if command -v terraform &>/dev/null && [[ -d "$TF_ENV_DIR" ]]; then
    echo -e "${CYAN}ℹ INFO${NC}  Resolving Terraform outputs from ${TF_ENV_DIR} …"
    TF_JSON=$(terraform -chdir="$TF_ENV_DIR" output -json 2>/dev/null || true)
    if [[ -n "$TF_JSON" && "$TF_JSON" != "{}" ]]; then
      ALB_RAW=$(echo "$TF_JSON" | jq -r '.alb_dns_name.value // empty' 2>/dev/null || true)
      if [[ -n "$ALB_RAW" ]]; then
        export API_BASE_URL="http://${ALB_RAW}"
        echo -e "${CYAN}ℹ INFO${NC}  API_BASE_URL set from TF: ${API_BASE_URL}"
      fi

      # Also export S3 bucket name for 03_upload.sh S3 verification
      S3_FROM_TF=$(echo "$TF_JSON" | jq -r '.s3_bucket_id.value // empty' 2>/dev/null || true)
      if [[ -n "$S3_FROM_TF" ]]; then
        export S3_DOC_BUCKET="$S3_FROM_TF"
        echo -e "${CYAN}ℹ INFO${NC}  S3_DOC_BUCKET set from TF: ${S3_DOC_BUCKET}"
      fi
    else
      echo -e "${YELLOW}⚠ WARN${NC}  Could not load Terraform outputs."
    fi
  else
    echo -e "${YELLOW}⚠ WARN${NC}  Terraform not available or environments/${ENVIRONMENT} not found."
  fi
fi

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo -e "${RED}✖ ERROR${NC}  API_BASE_URL could not be resolved."
  echo "  Set it manually or ensure Terraform outputs include 'alb_dns_name':"
  echo ""
  echo "  export API_BASE_URL=http://parseon-dev-alb-1234.us-east-1.elb.amazonaws.com"
  echo ""
  exit 1
fi

export API_BASE_URL
export TEST_USERNAME
export TEST_PASSWORD
export S3_DOC_BUCKET="${S3_DOC_BUCKET:-${PROJECT_NAME}-${ENVIRONMENT}-bucket}"

# ── Run all check scripts ─────────────────────────────────────────────────────
CHECKS_DIR="$SCRIPT_DIR/phase2"
SCRIPTS=(
  "01_health.sh"
  "02_auth.sh"
  "03_upload.sh"
  "04_process.sh"
  "05_golden_workflow.sh"
)

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0
FAILED_SCRIPTS=""
SKIPPED_SCRIPTS=""

echo ""
echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║  Parseon Phase 2 Application Smoke Tests        ║${NC}"
echo -e "${BOLD}${BLUE}║  Environment : ${ENVIRONMENT}  •  API : ${API_BASE_URL}${NC}"
echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════╝${NC}"

for script in "${SCRIPTS[@]}"; do
  script_path="$CHECKS_DIR/$script"
  if [[ ! -f "$script_path" ]]; then
    echo -e "${YELLOW}⚠ WARN${NC}  Script not found: $script — skipping"
    SKIPPED_SCRIPTS="$SKIPPED_SCRIPTS $script"
    continue
  fi

  script_output=$(bash "$script_path" 2>&1)
  script_exit=$?
  echo "$script_output"

  fail_count=$(echo "$script_output" | grep -oE '[0-9]+ failure' | grep -oE '^[0-9]+' | head -1 || true)
  warn_count=$(echo "$script_output" | grep -oE '[0-9]+ warning' | grep -oE '^[0-9]+' | head -1 || true)
  fail_count="${fail_count:-0}"
  warn_count="${warn_count:-0}"

  TOTAL_FAIL=$((TOTAL_FAIL + fail_count))
  TOTAL_WARN=$((TOTAL_WARN + warn_count))
  if [[ $script_exit -eq 0 ]]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    FAILED_SCRIPTS="$FAILED_SCRIPTS $script"
  fi
done

# ── Overall summary ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 2 SUMMARY${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
for script in "${SCRIPTS[@]}"; do
  if echo "$SKIPPED_SCRIPTS" | grep -qF "$script"; then
    echo -e "  ${YELLOW}–${NC}  $script  (skipped)"
  elif echo "$FAILED_SCRIPTS" | grep -qF "$script"; then
    echo -e "  ${RED}✖${NC}  $script"
  else
    echo -e "  ${GREEN}✔${NC}  $script"
  fi
done
echo ""

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_WARN -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✔ All smoke tests passed — application is healthy.${NC}"
  exit 0
elif [[ $TOTAL_FAIL -eq 0 ]]; then
  echo -e "${YELLOW}${BOLD}  ⚠ All smoke tests passed with $TOTAL_WARN warning(s).${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}  ✖ $TOTAL_FAIL failure(s) across smoke tests. Review output above.${NC}"
  exit 1
fi
