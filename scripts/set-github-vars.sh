#!/usr/bin/env bash
# set-github-vars.sh
#
# Reads Terraform outputs from both environments and sets all GitHub Actions
# variables in the parseon-web-ui repository using the GitHub CLI.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - Terraform state accessible (HCP Cloud workspace configured)
#
# Usage:
#   ./scripts/set-github-vars.sh

set -euo pipefail

REPO="maroonvillage/parseon-web-ui"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="${INFRA_DIR}/environments/dev"
PROD_DIR="${INFRA_DIR}/environments/prod"

# ── helpers ──────────────────────────────────────────────────────────────────

check_prereqs() {
  if ! command -v gh &>/dev/null; then
    echo "❌  GitHub CLI (gh) not found. Install it: brew install gh" >&2
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    echo "❌  Not authenticated with gh. Run: gh auth login" >&2
    exit 1
  fi
  if ! command -v terraform &>/dev/null; then
    echo "❌  terraform not found in PATH." >&2
    exit 1
  fi
}

tf_output() {
  local dir="$1"
  local key="$2"
  terraform -chdir="$dir" output -raw "$key" 2>/dev/null
}

set_repo_var() {
  local name="$1"
  local value="$2"
  echo "  → [repo] $name"
  gh variable set "$name" --body "$value" --repo "$REPO"
}

set_env_var() {
  local env="$1"
  local name="$2"
  local value="$3"
  echo "  → [$env] $name"
  gh variable set "$name" --body "$value" --repo "$REPO" --env "$env"
}

# ── main ─────────────────────────────────────────────────────────────────────

check_prereqs

echo ""
echo "📖  Reading Terraform outputs from dev environment…"
DEV_FRONTEND_ROLE_ARN=$(tf_output "$DEV_DIR" "frontend_actions_role_arn")
STAGING_BUCKET_ID=$(tf_output "$DEV_DIR" "frontend_bucket_id")
STAGING_CF_DIST_ID=$(tf_output "$DEV_DIR" "cloudfront_distribution_id")
STAGING_CF_DOMAIN=$(tf_output "$DEV_DIR" "cloudfront_domain")

echo "📖  Reading Terraform outputs from prod environment…"
PROD_FRONTEND_ROLE_ARN=$(tf_output "$PROD_DIR" "frontend_actions_role_arn")
PROD_BUCKET_ID=$(tf_output "$PROD_DIR" "frontend_bucket_id")
PROD_CF_DIST_ID=$(tf_output "$PROD_DIR" "cloudfront_distribution_id")

# Validate nothing is empty
for var_name in DEV_FRONTEND_ROLE_ARN STAGING_BUCKET_ID STAGING_CF_DIST_ID STAGING_CF_DOMAIN \
                PROD_FRONTEND_ROLE_ARN PROD_BUCKET_ID PROD_CF_DIST_ID; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "❌  Empty value for ${var_name}. Has terraform apply been run in both environments?" >&2
    exit 1
  fi
done

echo ""
echo "🔧  Setting repo-level variables in ${REPO}…"
set_repo_var "AWS_REGION"                    "us-east-1"
set_repo_var "REACT_APP_API_BASE_URL_STAGING" "https://${STAGING_CF_DOMAIN}/api"

echo ""
echo "🔧  Setting 'dev' environment variables…"
set_env_var "dev" "PARSEON_DEV_FRONTEND_ROLE_ARN"       "$DEV_FRONTEND_ROLE_ARN"
set_env_var "dev" "FRONTEND_BUCKET_ID_STAGING"           "$STAGING_BUCKET_ID"
set_env_var "dev" "CLOUDFRONT_DISTRIBUTION_ID_STAGING"   "$STAGING_CF_DIST_ID"

echo ""
echo "🔧  Setting 'prod' environment variables…"
set_env_var "prod" "PARSEON_PROD_FRONTEND_ROLE_ARN"     "$PROD_FRONTEND_ROLE_ARN"
set_env_var "prod" "FRONTEND_BUCKET_ID_PROD"             "$PROD_BUCKET_ID"
set_env_var "prod" "CLOUDFRONT_DISTRIBUTION_ID_PROD"     "$PROD_CF_DIST_ID"

echo ""
echo "✅  All GitHub Actions variables set successfully."
echo ""
echo "   Run this to verify:"
echo "   gh variable list --repo ${REPO}"
echo "   gh variable list --repo ${REPO} --env dev"
echo "   gh variable list --repo ${REPO} --env prod"
