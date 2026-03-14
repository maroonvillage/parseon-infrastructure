#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 07: Application Load Balancer (ALB)
#
# Verifies:
#   - ALB exists and is in 'active' state
#   - Listener exists (HTTP:80, and HTTPS:443 if cert configured)
#   - Target group exists
#   - Target health (ECS tasks registered and healthy)
#   - HTTP health check responds correctly
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "07 · ALB (Application Load Balancer)"

# ── 1. Find the ALB ───────────────────────────────────────────────────────────
info "Looking up ALB: ${ALB_NAME}"
ALB=$(aws elbv2 describe-load-balancers \
  --names "$ALB_NAME" \
  --region "$AWS_REGION" \
  --query "LoadBalancers[0]" \
  --output json 2>/dev/null || echo "{}")

ALB_ARN=$(echo "$ALB"     | jq -r '.LoadBalancerArn // ""')
ALB_DNS=$(echo "$ALB"     | jq -r '.DNSName // ""')
ALB_STATE=$(echo "$ALB"   | jq -r '.State.Code // "NOT_FOUND"')
ALB_SCHEME=$(echo "$ALB"  | jq -r '.Scheme // ""')
ALB_TYPE=$(echo "$ALB"    | jq -r '.Type // ""')

if [[ -n "$ALB_ARN" && "$ALB_ARN" != "null" ]]; then
  pass "ALB '${ALB_NAME}' found."
  info "ARN    : $ALB_ARN"
  info "DNS    : $ALB_DNS"
  info "Scheme : $ALB_SCHEME  Type: $ALB_TYPE"
else
  fail "ALB '${ALB_NAME}' not found in region ${AWS_REGION}."
  summarize "ALB"
  exit $?
fi

# ── 2. State ─────────────────────────────────────────────────────────────────
if [[ "$ALB_STATE" == "active" ]]; then
  pass "ALB state is active."
else
  fail "ALB state is '${ALB_STATE}' (expected active)."
fi

# ── 3. Listeners ─────────────────────────────────────────────────────────────
LISTENERS=$(aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --region "$AWS_REGION" \
  --query "Listeners[*].{Port:Port,Protocol:Protocol,Action:DefaultActions[0].Type}" \
  --output json 2>/dev/null || echo "[]")

LISTENER_COUNT=$(echo "$LISTENERS" | jq 'length')
if [[ "$LISTENER_COUNT" -gt 0 ]]; then
  pass "$LISTENER_COUNT listener(s) configured."
  echo "$LISTENERS" | jq -r '.[] | "    port=\(.Port) protocol=\(.Protocol) action=\(.Action)"' \
    | while read -r l; do info "$l"; done

  HAS_HTTP=$(echo "$LISTENERS" | jq '[.[] | select(.Port == 80)] | length')
  HAS_HTTPS=$(echo "$LISTENERS" | jq '[.[] | select(.Port == 443)] | length')

  if [[ "$HAS_HTTP" -gt 0 ]]; then
    pass "HTTP:80 listener is present."
  else
    warn "No HTTP:80 listener — traffic may not be reaching the ALB."
  fi
  if [[ "$HAS_HTTPS" -gt 0 ]]; then
    pass "HTTPS:443 listener is present."
  else
    info "No HTTPS:443 listener — expected if ACM certificate has not been provisioned yet."
  fi
else
  fail "No listeners found on ALB — traffic cannot reach backend."
fi

# ── 4. Target groups ─────────────────────────────────────────────────────────
TG_NAME="${NAME_PREFIX}-tg"
TG=$(aws elbv2 describe-target-groups \
  --names "$TG_NAME" \
  --region "$AWS_REGION" \
  --query "TargetGroups[0]" \
  --output json 2>/dev/null || echo "{}")

TG_ARN=$(echo "$TG"  | jq -r '.TargetGroupArn // ""')
TG_HC_PATH=$(echo "$TG" | jq -r '.HealthCheckPath // "/"')
TG_TYPE=$(echo "$TG" | jq -r '.TargetType // ""')

if [[ -n "$TG_ARN" && "$TG_ARN" != "null" ]]; then
  pass "Target group '${TG_NAME}' exists."
  info "Target type   : $TG_TYPE"
  info "Health check  : $TG_HC_PATH"
else
  fail "Target group '${TG_NAME}' not found."
  summarize "ALB"
  exit $?
fi

# ── 5. Target health ─────────────────────────────────────────────────────────
HEALTH=$(aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region "$AWS_REGION" \
  --query "TargetHealthDescriptions[*].{Id:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output json 2>/dev/null || echo "[]")

TARGET_COUNT=$(echo "$HEALTH" | jq 'length')
if [[ "$TARGET_COUNT" -eq 0 ]]; then
  warn "No targets registered in target group — ECS tasks may not be running yet."
else
  HEALTHY=$(echo "$HEALTH" | jq '[.[] | select(.State == "healthy")] | length')
  UNHEALTHY=$(echo "$HEALTH" | jq '[.[] | select(.State == "unhealthy")] | length')
  INITIAL=$(echo "$HEALTH"  | jq '[.[] | select(.State == "initial")] | length')
  DRAINING=$(echo "$HEALTH" | jq '[.[] | select(.State == "draining")] | length')

  info "Targets: $TARGET_COUNT total  |  healthy: $HEALTHY  unhealthy: $UNHEALTHY  initial: $INITIAL  draining: $DRAINING"

  if [[ "$HEALTHY" -gt 0 ]]; then
    pass "$HEALTHY healthy target(s) registered."
  elif [[ "$INITIAL" -gt 0 ]]; then
    warn "Targets are still in initial health check state — may need more time."
  else
    fail "No healthy targets — backend may be failing health checks."
    # Print unhealthy reasons
    echo "$HEALTH" | jq -r '.[] | select(.State != "healthy") | "    \(.Id):\(.Port) → \(.State) (\(.Reason // "no reason"))"' \
      | while read -r r; do warn "$r"; done
  fi
fi

# ── 6. HTTP reachability via ALB DNS ──────────────────────────────────────────
if command -v curl &>/dev/null && [[ -n "$ALB_DNS" && "$ALB_DNS" != "null" ]]; then
  info "Checking HTTP response for http://${ALB_DNS}/health …"
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 "http://${ALB_DNS}/health" 2>/dev/null || echo "000")
  if [[ "$HTTP_STATUS" =~ ^(200|204)$ ]]; then
    pass "ALB health endpoint returned HTTP $HTTP_STATUS."
  elif [[ "$HTTP_STATUS" == "404" ]]; then
    warn "ALB returned 404 on /health — check health check path in ALB target group."
  elif [[ "$HTTP_STATUS" == "502" || "$HTTP_STATUS" == "503" ]]; then
    fail "ALB returned $HTTP_STATUS — backend container is not reachable or not running."
  elif [[ "$HTTP_STATUS" == "000" ]]; then
    warn "Could not reach ALB DNS (connection failed or timed out)."
  else
    info "ALB health check returned HTTP $HTTP_STATUS."
  fi
fi

summarize "ALB"
