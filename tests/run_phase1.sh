#!/usr/bin/env bash
# =============================================================================
# Phase 1: Infrastructure Verification — Orchestrator
#
# Runs all post-Terraform AWS resource health checks for a given environment.
#
# Usage:
#   ./tests/run_phase1.sh [dev|prod]
#
# Options:
#   ENVIRONMENT=prod ./tests/run_phase1.sh    # override environment
#   ./tests/run_phase1.sh prod               # positional arg also works
#
# Requirements:
#   - AWS CLI v2 installed and authenticated
#   - jq installed (brew install jq)
#   - Terraform CLI installed (for live output resolution)
#   - Run from the repo root or the tests/ directory
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Allow environment override via positional arg
if [[ "${1:-}" != "" ]]; then
  export ENVIRONMENT="$1"
fi

source "$SCRIPT_DIR/config.sh"
require_aws_cli

# ── Optional: resolve live Terraform outputs ───────────────────────────────────
# If run from the repo root and terraform is available, pull live output values
# so HTTP checks use the actual CloudFront domain / ALB DNS rather than
# AWS-derived lookups.
TF_ENV_DIR="$SCRIPT_DIR/../environments/${ENVIRONMENT}"
if command -v terraform &>/dev/null && [[ -d "$TF_ENV_DIR" ]]; then
  echo -e "${CYAN}ℹ INFO${NC}  Resolving Terraform outputs from ${TF_ENV_DIR} …"
  TF_JSON=$(terraform -chdir="$TF_ENV_DIR" output -json 2>/dev/null || true)
  if [[ -n "$TF_JSON" && "$TF_JSON" != "{}" ]]; then
    export CLOUDFRONT_DOMAIN
    export ALB_DNS_NAME
    export SQS_QUEUE_URL
    export ECS_CLUSTER_NAME
    export ECS_SERVICE_NAME
    export ECR_REPOSITORY_URL
    export S3_DOC_BUCKET
    export S3_FRONTEND_BUCKET

    CLOUDFRONT_DOMAIN=$(echo "$TF_JSON" | jq -r '.cloudfront_domain.value // empty' 2>/dev/null || true)
    ALB_DNS_NAME=$(echo "$TF_JSON" | jq -r '.alb_dns_name.value // empty' 2>/dev/null || true)
    SQS_QUEUE_URL=$(echo "$TF_JSON" | jq -r '.sqs_queue_url.value // empty' 2>/dev/null || true)
    ECS_CLUSTER_NAME=$(echo "$TF_JSON" | jq -r '.ecs_cluster_name.value // empty' 2>/dev/null || echo "$ECS_CLUSTER_NAME")
    ECS_SERVICE_NAME=$(echo "$TF_JSON" | jq -r '.ecs_service_name.value // empty' 2>/dev/null || echo "$ECS_SERVICE_NAME")
    ECR_REPOSITORY_URL=$(echo "$TF_JSON" | jq -r '.ecr_repository_url.value // empty' 2>/dev/null || true)
    S3_DOC_BUCKET=$(echo "$TF_JSON"  | jq -r '.s3_bucket_id.value // empty' 2>/dev/null || echo "$S3_DOC_BUCKET")
    S3_FRONTEND_BUCKET=$(echo "$TF_JSON" | jq -r '.frontend_bucket_id.value // empty' 2>/dev/null || echo "$S3_FRONTEND_BUCKET")
    echo -e "${CYAN}ℹ INFO${NC}  Terraform outputs loaded."
  else
    echo -e "${YELLOW}⚠ WARN${NC}  Could not load Terraform outputs — falling back to derived names."
  fi
else
  echo -e "${YELLOW}⚠ WARN${NC}  Terraform not available or environments/${ENVIRONMENT} not found — using derived names."
fi

# ── Run all check scripts ──────────────────────────────────────────────────────
CHECKS_DIR="$SCRIPT_DIR/phase1"
SCRIPTS=(
  "01_cloudfront.sh"
  "02_s3.sh"
  "03_ecs.sh"
  "04_ecr.sh"
  "05_sqs.sh"
  "06_iam.sh"
  "07_alb.sh"
  "08_networking.sh"
)

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0
FAILED_SCRIPTS=""
SKIPPED_SCRIPTS=""

echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║  Parseon Phase 1 Infrastructure Verification  ║${NC}"
echo -e "${BOLD}${BLUE}║  Environment : ${ENVIRONMENT}  •  Region : ${AWS_REGION}         ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${NC}"

for script in "${SCRIPTS[@]}"; do
  script_path="$CHECKS_DIR/$script"
  if [[ ! -f "$script_path" ]]; then
    echo -e "${YELLOW}⚠ WARN${NC}  Script not found: $script — skipping"
    SKIPPED_SCRIPTS="$SKIPPED_SCRIPTS $script"
    continue
  fi
  # Run in a subshell so each script's FAILURES/WARNINGS are independent
  script_output=$(bash "$script_path" 2>&1)
  script_exit=$?
  echo "$script_output"

  # Extract failure/warning counts (macOS-compatible: no grep -P)
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
echo -e "${BOLD}  PHASE 1 SUMMARY${NC}"
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
  echo -e "${GREEN}${BOLD}  ✔ All checks passed — infrastructure is healthy.${NC}"
  exit 0
elif [[ $TOTAL_FAIL -eq 0 ]]; then
  echo -e "${YELLOW}${BOLD}  ⚠ All checks passed with $TOTAL_WARN warning(s).${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}  ✖ $TOTAL_FAIL failure(s) across checks. Review output above.${NC}"
  exit 1
fi
