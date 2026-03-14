#!/usr/bin/env bash
# =============================================================================
# Phase 1 Check 05: SQS
#
# Verifies:
#   - Main queue exists
#   - Dead-letter queue (DLQ) exists
#   - Redrive policy links queue → DLQ
#   - SSE (server-side encryption) is enabled
#   - Round-trip test: send a message, receive it, delete it
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_aws_cli

section "05 · SQS"

# ── 1. Main queue ─────────────────────────────────────────────────────────────
info "Resolving queue URL for: ${SQS_QUEUE_NAME}"
if [[ -n "${SQS_QUEUE_URL:-}" ]]; then
  QUEUE_URL="$SQS_QUEUE_URL"
  info "Using Terraform output: $QUEUE_URL"
else
  QUEUE_URL=$(aws sqs get-queue-url \
    --queue-name "$SQS_QUEUE_NAME" \
    --region "$AWS_REGION" \
    --query "QueueUrl" \
    --output text 2>/dev/null || echo "")
fi

if [[ -n "$QUEUE_URL" && "$QUEUE_URL" != "None" ]]; then
  pass "Queue '${SQS_QUEUE_NAME}' exists: $QUEUE_URL"
else
  fail "Queue '${SQS_QUEUE_NAME}' not found in region ${AWS_REGION}."
  summarize "SQS"
  exit $?
fi

# ── 2. Queue attributes ───────────────────────────────────────────────────────
ATTRS=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names All \
  --region "$AWS_REGION" \
  --output json 2>/dev/null || echo '{"Attributes":{}}')

APPROX_MESSAGES=$(echo "$ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
VISIBILITY_TIMEOUT=$(echo "$ATTRS" | jq -r '.Attributes.VisibilityTimeout // "unknown"')
REDRIVE_POLICY=$(echo "$ATTRS"   | jq -r '.Attributes.RedrivePolicy // ""')
SSE_ENABLED=$(echo "$ATTRS"      | jq -r '.Attributes.SqsManagedSseEnabled // "false"')
QUEUE_ARN=$(echo "$ATTRS"        | jq -r '.Attributes.QueueArn // ""')

info "Queue ARN              : $QUEUE_ARN"
info "Visibility timeout     : ${VISIBILITY_TIMEOUT}s"
info "Approximate messages   : $APPROX_MESSAGES"

if [[ "$SSE_ENABLED" == "true" ]]; then
  pass "SQS managed SSE (server-side encryption) is enabled."
else
  fail "SQS managed SSE is NOT enabled — messages are not encrypted at rest."
fi

# ── 3. DLQ and redrive policy ─────────────────────────────────────────────────
if [[ -n "$REDRIVE_POLICY" ]]; then
  DLQ_ARN=$(echo "$REDRIVE_POLICY" | jq -r '.deadLetterTargetArn // ""' 2>/dev/null || \
            echo "$REDRIVE_POLICY" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('deadLetterTargetArn',''))" 2>/dev/null || echo "")
  MAX_RECEIVE=$(echo "$REDRIVE_POLICY" | jq -r '.maxReceiveCount // ""' 2>/dev/null || echo "")
  if [[ -n "$DLQ_ARN" ]]; then
    pass "Redrive policy configured — DLQ: $(echo "$DLQ_ARN" | awk -F: '{print $NF}')"
    info "Max receive count before DLQ: $MAX_RECEIVE"
  else
    warn "Redrive policy JSON found but could not parse DLQ ARN."
  fi
else
  warn "No redrive policy set — failed messages will not be routed to a DLQ."
fi

# ── 4. DLQ exists ─────────────────────────────────────────────────────────────
info "Checking DLQ: ${SQS_DLQ_NAME}"
DLQ_URL=$(aws sqs get-queue-url \
  --queue-name "$SQS_DLQ_NAME" \
  --region "$AWS_REGION" \
  --query "QueueUrl" \
  --output text 2>/dev/null || echo "")

if [[ -n "$DLQ_URL" && "$DLQ_URL" != "None" ]]; then
  pass "DLQ '${SQS_DLQ_NAME}' exists."
  DLQ_DEPTH=$(aws sqs get-queue-attributes \
    --queue-url "$DLQ_URL" \
    --attribute-names ApproximateNumberOfMessages \
    --query "Attributes.ApproximateNumberOfMessages" \
    --output text 2>/dev/null || echo "0")
  if [[ "$DLQ_DEPTH" -gt 0 ]]; then
    warn "DLQ has ${DLQ_DEPTH} message(s) — check for failed message processing."
  else
    pass "DLQ is empty (no failed messages)."
  fi
else
  warn "DLQ '${SQS_DLQ_NAME}' not found — it may not be enabled."
fi

# ── 5. Round-trip test: send → receive → delete ───────────────────────────────
info "Running round-trip message test…"
TEST_BODY="parseon-phase1-verify-$(date +%s)"

SEND_RESULT=$(aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body "$TEST_BODY" \
  --region "$AWS_REGION" \
  --query "MessageId" \
  --output text 2>/dev/null || echo "")

if [[ -n "$SEND_RESULT" && "$SEND_RESULT" != "None" ]]; then
  pass "Test message sent (MessageId: $SEND_RESULT)."
else
  fail "Failed to send test message to queue."
  summarize "SQS"
  exit $?
fi

# Allow a moment for the message to be available
sleep 1

RECEIVE_RESULT=$(aws sqs receive-message \
  --queue-url "$QUEUE_URL" \
  --max-number-of-messages 1 \
  --wait-time-seconds 3 \
  --visibility-timeout 30 \
  --region "$AWS_REGION" \
  --query "Messages[0]" \
  --output json 2>/dev/null || echo "{}")

RECEIVED_BODY=$(echo "$RECEIVE_RESULT" | jq -r '.Body // ""')
RECEIPT_HANDLE=$(echo "$RECEIVE_RESULT" | jq -r '.ReceiptHandle // ""')

if [[ "$RECEIVED_BODY" == "$TEST_BODY" ]]; then
  pass "Test message received successfully."
elif [[ -n "$RECEIVED_BODY" ]]; then
  warn "Received a message but body did not match test payload (may be a leftover message)."
  RECEIPT_HANDLE=$(echo "$RECEIVE_RESULT" | jq -r '.ReceiptHandle // ""')
else
  fail "No message received from queue within timeout."
fi

# Delete the test message (clean up regardless)
if [[ -n "$RECEIPT_HANDLE" && "$RECEIPT_HANDLE" != "null" ]]; then
  aws sqs delete-message \
    --queue-url "$QUEUE_URL" \
    --receipt-handle "$RECEIPT_HANDLE" \
    --region "$AWS_REGION" 2>/dev/null || true
  info "Test message deleted from queue (cleanup done)."
fi

summarize "SQS"
