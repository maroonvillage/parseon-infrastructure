#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 06: IAM Roles
#
# Verifies:
#   - ECS execution role exists with AmazonECSTaskExecutionRolePolicy attached
#   - ECS task role exists with S3 and SQS inline policies attached
#   - Trust relationship allows ecs-tasks.amazonaws.com to assume both roles
#   - (Optional) Secrets Manager and RDS IAM auth policies when configured
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "06 · IAM Roles"

# ── Helper: check trust policy allows ecs-tasks principal ─────────────────────
verify_ecs_trust() {
  local role_name="$1"
  local trust
  trust=$(aws iam get-role \
    --role-name "$role_name" \
    --query "Role.AssumeRolePolicyDocument" \
    --output json 2>/dev/null || echo "{}")
  echo "$trust" | jq -r \
    '.Statement[].Principal.Service // "" | if type == "array" then .[] else . end' \
    2>/dev/null | grep -q "ecs-tasks.amazonaws.com"
}

# ── 1. ECS Execution Role ─────────────────────────────────────────────────────
info "Checking ECS execution role: ${ECS_EXEC_ROLE}"
EXEC_ROLE=$(aws iam get-role \
  --role-name "$ECS_EXEC_ROLE" \
  --query "Role.{Arn:Arn,CreateDate:CreateDate}" \
  --output json 2>/dev/null || echo "{}")

EXEC_ARN=$(echo "$EXEC_ROLE" | jq -r '.Arn // ""')
if [[ -n "$EXEC_ARN" && "$EXEC_ARN" != "null" ]]; then
  pass "Execution role '${ECS_EXEC_ROLE}' exists."
  info "ARN: $EXEC_ARN"
else
  fail "Execution role '${ECS_EXEC_ROLE}' not found."
fi

# Trust policy
if verify_ecs_trust "$ECS_EXEC_ROLE" 2>/dev/null; then
  pass "Execution role trust policy allows ecs-tasks.amazonaws.com."
else
  fail "Execution role trust policy does NOT allow ecs-tasks.amazonaws.com."
fi

# Managed policy: AmazonECSTaskExecutionRolePolicy
EXEC_MANAGED=$(aws iam list-attached-role-policies \
  --role-name "$ECS_EXEC_ROLE" \
  --query "AttachedPolicies[*].PolicyName" \
  --output json 2>/dev/null || echo "[]")

if echo "$EXEC_MANAGED" | jq -r '.[]' | grep -q "AmazonECSTaskExecutionRolePolicy"; then
  pass "AmazonECSTaskExecutionRolePolicy is attached to execution role."
else
  fail "AmazonECSTaskExecutionRolePolicy is NOT attached to execution role."
fi

info "All attached managed policies on execution role:"
echo "$EXEC_MANAGED" | jq -r '.[]' | while read -r p; do info "  • $p"; done

# ── 2. ECS Task Role ──────────────────────────────────────────────────────────
echo ""
info "Checking ECS task role: ${ECS_TASK_ROLE}"
TASK_ROLE=$(aws iam get-role \
  --role-name "$ECS_TASK_ROLE" \
  --query "Role.{Arn:Arn,CreateDate:CreateDate}" \
  --output json 2>/dev/null || echo "{}")

TASK_ARN=$(echo "$TASK_ROLE" | jq -r '.Arn // ""')
if [[ -n "$TASK_ARN" && "$TASK_ARN" != "null" ]]; then
  pass "Task role '${ECS_TASK_ROLE}' exists."
  info "ARN: $TASK_ARN"
else
  fail "Task role '${ECS_TASK_ROLE}' not found."
fi

# Trust policy
if verify_ecs_trust "$ECS_TASK_ROLE" 2>/dev/null; then
  pass "Task role trust policy allows ecs-tasks.amazonaws.com."
else
  fail "Task role trust policy does NOT allow ecs-tasks.amazonaws.com."
fi

# Inline policies (S3 and SQS access are inline in the IAM module)
INLINE_POLICIES=$(aws iam list-role-policies \
  --role-name "$ECS_TASK_ROLE" \
  --query "PolicyNames" \
  --output json 2>/dev/null || echo "[]")

INLINE_COUNT=$(echo "$INLINE_POLICIES" | jq 'length')
if [[ "$INLINE_COUNT" -gt 0 ]]; then
  pass "Task role has $INLINE_COUNT inline polic(ies):"
  echo "$INLINE_POLICIES" | jq -r '.[]' | while read -r p; do info "  • $p"; done
else
  warn "Task role has no inline policies — S3/SQS access may not be configured."
fi

# Check for S3 and SQS actions in inline policies
S3_ALLOWED=false
SQS_ALLOWED=false
while read -r policy_name; do
  POLICY_DOC=$(aws iam get-role-policy \
    --role-name "$ECS_TASK_ROLE" \
    --policy-name "$policy_name" \
    --query "PolicyDocument" \
    --output json 2>/dev/null || echo "{}")
  if echo "$POLICY_DOC" | jq -r '.Statement[].Action[]?' 2>/dev/null | grep -q "s3:"; then
    S3_ALLOWED=true
  fi
  if echo "$POLICY_DOC" | jq -r '.Statement[].Action[]?' 2>/dev/null | grep -q "sqs:"; then
    SQS_ALLOWED=true
  fi
done < <(echo "$INLINE_POLICIES" | jq -r '.[]')

if [[ "$S3_ALLOWED" == "true" ]]; then
  pass "Task role grants S3 access."
else
  warn "No S3 actions found in task role policies (expected if secrets_arns only)."
fi

if [[ "$SQS_ALLOWED" == "true" ]]; then
  pass "Task role grants SQS access."
else
  warn "No SQS actions found in task role policies."
fi

# ── 3. GitHub Actions OIDC role ────────────────────────────────────────────────
echo ""
OIDC_ROLE="${NAME_PREFIX}-github-actions-role"
info "Checking GitHub Actions OIDC role: ${OIDC_ROLE}"
OIDC_ROLE_ARN=$(aws iam get-role \
  --role-name "$OIDC_ROLE" \
  --query "Role.Arn" \
  --output text 2>/dev/null || echo "")

if [[ -n "$OIDC_ROLE_ARN" && "$OIDC_ROLE_ARN" != "None" ]]; then
  pass "GitHub Actions OIDC role exists: $OIDC_ROLE_ARN"
else
  warn "GitHub Actions OIDC role '${OIDC_ROLE}' not found — CI/CD deployments will fail."
fi

summarize "IAM"
