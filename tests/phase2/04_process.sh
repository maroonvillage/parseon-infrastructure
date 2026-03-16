#!/usr/bin/env bash
# =============================================================================
# Phase 2 Check 04: Document Processing
#
# Verifies:
#   - POST /api/files/process enqueues a job (returns job_id)
#   - Initial status is "queued" or "processing"
#   - Status eventually transitions to "completed" within timeout
#   - GET /api/files/process/{job_id}/results returns non-empty data
#   - Processing without auth returns 401
#
# Requirements:
#   - API_BASE_URL set
#   - TOKEN_FILE populated by 02_auth.sh
#   - ${TOKEN_FILE}.file_id populated by 03_upload.sh
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_api_url

section "04 · Document Processing"

# ── Token & file_id ───────────────────────────────────────────────────────────
TOKEN=$(read_token)
if [[ -z "$TOKEN" ]]; then
  fail "No auth token found. Run 02_auth.sh first."
  summarize "Process"
  exit $?
fi

FILE_ID_FILE="${TOKEN_FILE}.file_id"
if [[ ! -f "$FILE_ID_FILE" ]]; then
  fail "No file_id found. Run 03_upload.sh first."
  summarize "Process"
  exit $?
fi
FILE_ID=$(cat "$FILE_ID_FILE")
if [[ -z "$FILE_ID" ]]; then
  fail "file_id is empty. Run 03_upload.sh to upload a file first."
  summarize "Process"
  exit $?
fi
info "Using file_id: $FILE_ID"

# ── Helper ────────────────────────────────────────────────────────────────────
parse_status() { echo "$1" | grep -oE '__STATUS__[0-9]+' | tail -1 | grep -oE '[0-9]+'; }
parse_body()   { echo "$1" | grep -v '__STATUS__'; }

http_get_auth() {
  local url="$1" token="$2"
  curl -s -w "\n__STATUS__%{http_code}" --max-time 10 \
    -H "Authorization: Bearer $token" "$url" \
    2>/dev/null
}

# ── 1. Process without auth → 401 ────────────────────────────────────────────
info "Testing process without auth token (expect 401) …"
NO_AUTH_RESP=$(curl -s -w "\n__STATUS__%{http_code}" --max-time 10 \
  -H "Content-Type: application/json" \
  -d "{\"file_ids\":[\"${FILE_ID}\"],\"mode\":\"static\"}" \
  "${API_BASE_URL}/api/files/process" 2>/dev/null)
NO_AUTH_STATUS=$(parse_status "$NO_AUTH_RESP")

if [[ "$NO_AUTH_STATUS" == "401" || "$NO_AUTH_STATUS" == "403" ]]; then
  pass "Process without auth → HTTP $NO_AUTH_STATUS (correctly rejected)."
elif [[ "$NO_AUTH_STATUS" == "000" ]]; then
  fail "Connection failed. Check API_BASE_URL=${API_BASE_URL}"
  summarize "Process"
  exit $?
else
  fail "Process without auth → HTTP $NO_AUTH_STATUS (expected 401/403)."
fi

# ── 2. Submit processing job ──────────────────────────────────────────────────
echo ""
info "POST /api/files/process (mode=static) …"
PROCESS_PAYLOAD="{\"file_ids\":[\"${FILE_ID}\"],\"mode\":\"static\"}"
PROCESS_RESP=$(curl -s -w "\n__STATUS__%{http_code}" --max-time 15 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PROCESS_PAYLOAD" \
  "${API_BASE_URL}/api/files/process" 2>/dev/null)
PROCESS_STATUS=$(parse_status "$PROCESS_RESP")
PROCESS_BODY=$(parse_body "$PROCESS_RESP")

if [[ "$PROCESS_STATUS" == "200" || "$PROCESS_STATUS" == "201" || "$PROCESS_STATUS" == "202" ]]; then
  pass "POST /api/files/process → HTTP $PROCESS_STATUS"
else
  fail "POST /api/files/process → HTTP $PROCESS_STATUS. Body: $PROCESS_BODY"
  summarize "Process"
  exit $?
fi

JOB_ID=$(echo "$PROCESS_BODY" | jq -r '.job_id // ""' 2>/dev/null || true)
INITIAL_STATUS=$(echo "$PROCESS_BODY" | jq -r '.status // ""' 2>/dev/null || true)

if [[ -n "$JOB_ID" && "$JOB_ID" != "null" ]]; then
  pass "job_id returned: $JOB_ID"
else
  fail "job_id missing from process response. Body: $PROCESS_BODY"
  summarize "Process"
  exit $?
fi

if [[ "$INITIAL_STATUS" == "queued" || "$INITIAL_STATUS" == "processing" ]]; then
  pass "Initial job status: $INITIAL_STATUS"
else
  warn "Initial job status: $INITIAL_STATUS (expected 'queued' or 'processing')."
fi

# Persist for downstream scripts
echo "$JOB_ID" > "${TOKEN_FILE}.job_id"
info "job_id cached to ${TOKEN_FILE}.job_id"

# ── 3. Poll status until completed ───────────────────────────────────────────
echo ""
info "Polling status for job $JOB_ID (timeout: ${PROCESS_TIMEOUT}s, interval: ${POLL_INTERVAL}s) …"

ELAPSED=0
FINAL_STATUS=""
while [[ $ELAPSED -lt $PROCESS_TIMEOUT ]]; do
  POLL_RESP=$(http_get_auth "${API_BASE_URL}/api/files/process/${JOB_ID}/status" "$TOKEN")
  POLL_HTTP=$(parse_status "$POLL_RESP")
  POLL_BODY=$(parse_body "$POLL_RESP")

  if [[ "$POLL_HTTP" != "200" ]]; then
    fail "GET /api/files/process/${JOB_ID}/status → HTTP $POLL_HTTP"
    summarize "Process"
    exit $?
  fi

  CURRENT_STATUS=$(echo "$POLL_BODY" | jq -r '.status // ""' 2>/dev/null || true)

  if [[ "$CURRENT_STATUS" == "completed" ]]; then
    FINAL_STATUS="completed"
    break
  elif [[ "$CURRENT_STATUS" == "failed" ]]; then
    FINAL_STATUS="failed"
    FAIL_REASON=$(echo "$POLL_BODY" | jq -r '.error // .message // "unknown"' 2>/dev/null || echo "unknown")
    break
  fi

  info "  [${ELAPSED}s] status: $CURRENT_STATUS … waiting ${POLL_INTERVAL}s"
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [[ "$FINAL_STATUS" == "completed" ]]; then
  pass "Job completed in approximately ${ELAPSED}s."
elif [[ "$FINAL_STATUS" == "failed" ]]; then
  fail "Job failed. Reason: $FAIL_REASON"
  summarize "Process"
  exit $?
else
  fail "Job did not complete within ${PROCESS_TIMEOUT}s. Last status: $CURRENT_STATUS"
  summarize "Process"
  exit $?
fi

# ── 4. Retrieve results ───────────────────────────────────────────────────────
echo ""
info "GET /api/files/process/${JOB_ID}/results …"
RESULTS_RESP=$(http_get_auth "${API_BASE_URL}/api/files/process/${JOB_ID}/results" "$TOKEN")
RESULTS_HTTP=$(parse_status "$RESULTS_RESP")
RESULTS_BODY=$(parse_body "$RESULTS_RESP")

if [[ "$RESULTS_HTTP" == "200" ]]; then
  pass "GET /api/files/process/${JOB_ID}/results → HTTP 200"

  # Verify response is non-empty JSON
  if echo "$RESULTS_BODY" | jq . >/dev/null 2>&1; then
    CHARS=${#RESULTS_BODY}
    if [[ $CHARS -gt 10 ]]; then
      pass "Results response is valid JSON ($CHARS chars)."
    else
      warn "Results response seems very short ($CHARS chars): $RESULTS_BODY"
    fi
  else
    fail "Results response is not valid JSON: $RESULTS_BODY"
  fi
else
  fail "GET /api/files/process/${JOB_ID}/results → HTTP $RESULTS_HTTP. Body: $RESULTS_BODY"
fi

summarize "Process"
