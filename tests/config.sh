#!/usr/bin/env bash
# =============================================================================
# Shared configuration for Parseon infrastructure verification scripts.
# Source this file at the top of each check script:
#   source "$(cd "$(dirname "$0")/.." && pwd)/config.sh"
#
# Override any value by exporting the variable before sourcing, e.g.:
#   export ENVIRONMENT=prod && ./tests/run_phase1.sh
# =============================================================================

# ── Core settings ─────────────────────────────────────────────────────────────
PROJECT_NAME="${PROJECT_NAME:-parseon}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

# ── Derived resource names (match Terraform module naming conventions) ─────────
NAME_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-${NAME_PREFIX}-cluster}"
ECS_SERVICE_NAME="${ECS_SERVICE_NAME:-${NAME_PREFIX}-service}"
ECS_TASK_FAMILY="${ECS_TASK_FAMILY:-${NAME_PREFIX}-task}"
ECR_REPO_NAME="${ECR_REPO_NAME:-${PROJECT_NAME}-api}"

SQS_QUEUE_NAME="${SQS_QUEUE_NAME:-${NAME_PREFIX}-queue}"
SQS_DLQ_NAME="${SQS_DLQ_NAME:-${NAME_PREFIX}-dlq}"

S3_DOC_BUCKET="${S3_DOC_BUCKET:-${NAME_PREFIX}-bucket}"
S3_FRONTEND_BUCKET="${S3_FRONTEND_BUCKET:-${NAME_PREFIX}-frontend}"

ALB_NAME="${ALB_NAME:-${NAME_PREFIX}-alb}"
RDS_IDENTIFIER="${RDS_IDENTIFIER:-${NAME_PREFIX}-postgres}"

ECS_TASK_ROLE="${ECS_TASK_ROLE:-${NAME_PREFIX}-ecs-task-role}"
ECS_EXEC_ROLE="${ECS_EXEC_ROLE:-${NAME_PREFIX}-ecs-exec-role}"
CW_LOG_GROUP="${CW_LOG_GROUP:-/ecs/${NAME_PREFIX}}"

# ── Phase 2: Application smoke test settings ───────────────────────────────────
# API_BASE_URL is resolved from Terraform outputs (alb_dns_name) by run_phase2.sh.
# Override manually: export API_BASE_URL=https://your-alb-dns.us-east-1.elb.amazonaws.com
API_BASE_URL="${API_BASE_URL:-}"

# Test credentials — never hardcode real values here.
# Set these before running: export TEST_USERNAME=smoketest TEST_PASSWORD=yourpass
TEST_USERNAME="${TEST_USERNAME:-}"
TEST_PASSWORD="${TEST_PASSWORD:-}"

# Token file: auth script writes the token here; downstream scripts read it.
TOKEN_FILE="${TMPDIR:-/tmp}/parseon_smoke_token_${ENVIRONMENT}"

# Processing timeout for the golden workflow (seconds)
PROCESS_TIMEOUT="${PROCESS_TIMEOUT:-300}"
# Poll interval when waiting for a job to complete (seconds)
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# Require API base URL to be set and non-empty
require_api_url() {
  if [[ -z "$API_BASE_URL" ]]; then
    echo -e "${RED}ERROR: API_BASE_URL is not set.${NC}" >&2
    echo -e "       Export it or run via ./tests/run_phase2.sh which resolves it from Terraform outputs." >&2
    exit 1
  fi
  # Strip trailing slash for consistent URL construction
  API_BASE_URL="${API_BASE_URL%/}"
}

# Read the cached auth token written by 02_auth.sh
read_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    echo -e "${RED}ERROR: No auth token found at $TOKEN_FILE.${NC}" >&2
    echo -e "       Run tests/phase2/02_auth.sh first (or run_phase2.sh)." >&2
    exit 1
  fi
  cat "$TOKEN_FILE"
}

# ── Output helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Per-script failure/warning counters (each script resets these)
FAILURES=0
WARNINGS=0

pass()    { echo -e "  ${GREEN}✔ PASS${NC}  $1"; }
fail()    { echo -e "  ${RED}✖ FAIL${NC}  $1"; FAILURES=$((FAILURES + 1)); }
warn()    { echo -e "  ${YELLOW}⚠ WARN${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
info()    { echo -e "  ${CYAN}ℹ INFO${NC}  $1"; }
section() { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
            echo -e "${BOLD}${BLUE}  $1${NC}"; \
            echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# Prints a summary line and exits with code 1 if any failures occurred
summarize() {
  local label="${1:-Check}"
  echo ""
  if [[ $FAILURES -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✔ $label: all checks passed${NC}"
  elif [[ $FAILURES -eq 0 ]]; then
    echo -e "${YELLOW}${BOLD}  ⚠ $label: passed with $WARNINGS warning(s)${NC}"
  else
    echo -e "${RED}${BOLD}  ✖ $label: $FAILURES failure(s), $WARNINGS warning(s)${NC}"
  fi
  [[ $FAILURES -eq 0 ]]  # returns exit code 0 only if no failures
}

# Checks that the AWS CLI is installed and credentials are active
require_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo -e "${RED}ERROR: aws CLI not found. Install it from https://aws.amazon.com/cli/${NC}" >&2
    exit 1
  fi
  if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured or expired.${NC}" >&2
    echo -e "       Run: aws configure  (or set AWS_PROFILE / AWS_ACCESS_KEY_ID)${NC}" >&2
    exit 1
  fi
}
