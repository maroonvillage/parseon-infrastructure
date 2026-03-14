#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 03: ECS (Fargate)
#
# Verifies:
#   - ECS cluster exists and is ACTIVE
#   - ECS service is ACTIVE, running count matches desired
#   - At least one task is in RUNNING state
#   - Task definition container image and port are correct
#   - CloudWatch log group exists
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "03 · ECS (Fargate)"

# ── 1. Cluster ────────────────────────────────────────────────────────────────
info "Checking ECS cluster: ${ECS_CLUSTER_NAME}"
CLUSTER=$(aws ecs describe-clusters \
  --clusters "$ECS_CLUSTER_NAME" \
  --query "clusters[0]" \
  --output json 2>/dev/null || echo "{}")

CLUSTER_STATUS=$(echo "$CLUSTER" | jq -r '.status // "NOT_FOUND"')
CAPACITY_PROVIDERS=$(echo "$CLUSTER" | jq -r '.capacityProviders // [] | join(", ")')

if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
  pass "Cluster '${ECS_CLUSTER_NAME}' is ACTIVE."
else
  fail "Cluster '${ECS_CLUSTER_NAME}' status: ${CLUSTER_STATUS} (expected ACTIVE)."
  summarize "ECS"
  exit $?
fi

if echo "$CAPACITY_PROVIDERS" | grep -q "FARGATE"; then
  pass "FARGATE capacity provider is registered."
else
  warn "FARGATE capacity provider not found on cluster (got: ${CAPACITY_PROVIDERS:-none})."
fi

# ── 2. Service ────────────────────────────────────────────────────────────────
info "Checking ECS service: ${ECS_SERVICE_NAME}"
SERVICE=$(aws ecs describe-services \
  --cluster "$ECS_CLUSTER_NAME" \
  --services "$ECS_SERVICE_NAME" \
  --query "services[0]" \
  --output json 2>/dev/null || echo "{}")

SERVICE_STATUS=$(echo "$SERVICE" | jq -r '.status // "NOT_FOUND"')
DESIRED=$(echo "$SERVICE" | jq -r '.desiredCount // 0')
RUNNING=$(echo "$SERVICE" | jq -r '.runningCount // 0')
PENDING=$(echo "$SERVICE" | jq -r '.pendingCount // 0')
TASK_DEF_ARN=$(echo "$SERVICE" | jq -r '.taskDefinition // ""')

if [[ "$SERVICE_STATUS" == "ACTIVE" ]]; then
  pass "Service '${ECS_SERVICE_NAME}' is ACTIVE."
else
  fail "Service '${ECS_SERVICE_NAME}' status: ${SERVICE_STATUS} (expected ACTIVE)."
fi

info "Task counts — desired: $DESIRED  running: $RUNNING  pending: $PENDING"
if [[ "$RUNNING" -eq "$DESIRED" && "$DESIRED" -gt 0 ]]; then
  pass "Running task count ($RUNNING) matches desired ($DESIRED)."
elif [[ "$PENDING" -gt 0 ]]; then
  warn "Tasks are still starting — running: $RUNNING, pending: $PENDING, desired: $DESIRED."
elif [[ "$RUNNING" -eq 0 && "$DESIRED" -gt 0 ]]; then
  fail "No tasks running (desired: $DESIRED, running: $RUNNING)."
else
  pass "Task count acceptable: running=$RUNNING, desired=$DESIRED."
fi

# ── 3. Running tasks health ───────────────────────────────────────────────────
TASK_ARNS=$(aws ecs list-tasks \
  --cluster "$ECS_CLUSTER_NAME" \
  --service-name "$ECS_SERVICE_NAME" \
  --desired-status RUNNING \
  --query "taskArns" \
  --output json 2>/dev/null || echo "[]")

TASK_COUNT=$(echo "$TASK_ARNS" | jq 'length')
if [[ "$TASK_COUNT" -eq 0 ]]; then
  warn "No RUNNING tasks found — service may have just started or tasks are failing."
else
  pass "$TASK_COUNT RUNNING task(s) found."

  # Check health of first task
  FIRST_TASK=$(echo "$TASK_ARNS" | jq -r '.[0]')
  TASK_DETAIL=$(aws ecs describe-tasks \
    --cluster "$ECS_CLUSTER_NAME" \
    --tasks "$FIRST_TASK" \
    --query "tasks[0]" \
    --output json 2>/dev/null || echo "{}")

  LAST_STATUS=$(echo "$TASK_DETAIL" | jq -r '.lastStatus // "UNKNOWN"')
  HEALTH=$(echo "$TASK_DETAIL"     | jq -r '.healthStatus // "UNKNOWN"')
  STOP_REASON=$(echo "$TASK_DETAIL" | jq -r '.stopCode // ""')

  if [[ "$LAST_STATUS" == "RUNNING" ]]; then
    pass "Task last status: RUNNING."
  else
    fail "Task last status: ${LAST_STATUS} (expected RUNNING)."
  fi

  if [[ "$HEALTH" == "HEALTHY" ]]; then
    pass "Task health: HEALTHY."
  elif [[ "$HEALTH" == "UNKNOWN" ]]; then
    info "Task health status: UNKNOWN (health check may not be configured)."
  else
    warn "Task health: ${HEALTH}."
  fi
fi

# ── 4. Task definition ───────────────────────────────────────────────────────
if [[ -n "$TASK_DEF_ARN" ]]; then
  info "Task definition: $(echo "$TASK_DEF_ARN" | awk -F/ '{print $NF}')"
  TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF_ARN" \
    --query "taskDefinition" \
    --output json 2>/dev/null || echo "{}")

  CONTAINER_NAME=$(echo "$TASK_DEF" | jq -r '.containerDefinitions[0].name // ""')
  CONTAINER_IMAGE=$(echo "$TASK_DEF" | jq -r '.containerDefinitions[0].image // ""')
  CONTAINER_PORT=$(echo "$TASK_DEF" | jq -r '.containerDefinitions[0].portMappings[0].containerPort // ""')
  LOG_DRIVER=$(echo "$TASK_DEF" | jq -r '.containerDefinitions[0].logConfiguration.logDriver // ""')

  info "Container name  : $CONTAINER_NAME"
  info "Container image : $CONTAINER_IMAGE"
  info "Container port  : $CONTAINER_PORT"

  if [[ -n "$CONTAINER_IMAGE" && "$CONTAINER_IMAGE" != "null" ]]; then
    pass "Container image is set."
    # Warn if image is still a placeholder
    if echo "$CONTAINER_IMAGE" | grep -qiE "placeholder|example|dummy|YOUR"; then
      warn "Container image looks like a placeholder: ${CONTAINER_IMAGE}"
    fi
  else
    fail "Container image is not set in the task definition."
  fi

  if [[ "$CONTAINER_PORT" == "8000" ]]; then
    pass "Container port is 8000 (matches terraform.tfvars)."
  elif [[ -n "$CONTAINER_PORT" && "$CONTAINER_PORT" != "null" ]]; then
    info "Container port: $CONTAINER_PORT"
  else
    warn "Container port mapping is not set."
  fi

  if [[ "$LOG_DRIVER" == "awslogs" ]]; then
    pass "Log driver is awslogs (CloudWatch)."
  else
    fail "Log driver is '${LOG_DRIVER}' — expected awslogs."
  fi
else
  warn "Could not retrieve task definition ARN from service."
fi

# ── 5. CloudWatch log group ───────────────────────────────────────────────────
LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
  --log-group-name-prefix "$CW_LOG_GROUP" \
  --query "logGroups[?logGroupName=='${CW_LOG_GROUP}'].logGroupName" \
  --output text 2>/dev/null || echo "")

if [[ -n "$LOG_GROUP_EXISTS" ]]; then
  pass "CloudWatch log group '${CW_LOG_GROUP}' exists."
  # Check for recent log streams (indicates container actually logged something)
  STREAM_COUNT=$(aws logs describe-log-streams \
    --log-group-name "$CW_LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --max-items 5 \
    --query "length(logStreams)" \
    --output text 2>/dev/null || echo "0")
  if [[ "$STREAM_COUNT" -gt 0 ]]; then
    pass "Log group has $STREAM_COUNT log stream(s) — container has emitted logs."
  else
    warn "Log group exists but has no log streams yet (container may not have started)."
  fi
else
  fail "CloudWatch log group '${CW_LOG_GROUP}' not found."
fi

summarize "ECS"
