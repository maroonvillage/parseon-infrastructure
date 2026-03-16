#!/usr/bin/env bash
# =============================================================================
# Phase 2 Check 05: Golden Workflow (End-to-End)
#
# Runs the full "happy path" as a single self-contained test — no dependencies
# on intermediate state from other phase2 scripts.
#
#   Step 1  Login           POST /api/auth/login
#   Step 2  Health          GET  /health
#   Step 3  Upload          POST /api/files/upload
#   Step 4  Process         POST /api/files/process  (mode=static)
#   Step 5  Poll            GET  /api/files/process/{job_id}/status
#   Step 6  Results         GET  /api/files/process/{job_id}/results
#   Step 7  Logout / Revoke POST /api/auth/logout  (if endpoint exists)
#
# Requirements:
#   - API_BASE_URL set
#   - TEST_USERNAME and TEST_PASSWORD set
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_api_url

section "05 · Golden Workflow (E2E)"

if [[ -z "$TEST_USERNAME" || -z "$TEST_PASSWORD" ]]; then
  fail "TEST_USERNAME and TEST_PASSWORD must be set."
  summarize "Golden Workflow"
  exit $?
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
parse_status() { echo "$1" | grep -o '__STATUS__[0-9]*' | grep -o '[0-9]*'; }
parse_body()   { echo "$1" | sed 's/__STATUS__[0-9]*$//'; }

post_json() {
  local url="$1" payload="$2" token="${3:-}"
  local args=(-s -w "\n__STATUS__%{http_code}" --max-time 15
    -H "Content-Type: application/json" -d "$payload")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  curl "${args[@]}" "$url" 2>/dev/null || echo -e "\n__STATUS__000"
}

get_auth() {
  local url="$1" token="$2"
  curl -s -w "\n__STATUS__%{http_code}" --max-time 10 \
    -H "Authorization: Bearer $token" "$url" \
    2>/dev/null || echo -e "\n__STATUS__000"
}

step_fail() {
  local step="$1" msg="$2"
  fail "Step $step FAILED: $msg"
  summarize "Golden Workflow"
  exit $?
}

# ── Setup: ensure test PDF exists ─────────────────────────────────────────────
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_PDF="$FIXTURES_DIR/test_document.pdf"
if [[ ! -f "$TEST_PDF" ]]; then
  mkdir -p "$FIXTURES_DIR"
  printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]\n/Contents 4 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>\nendobj\n4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 12 Tf 100 750 Td (Parseon Smoke Test) Tj ET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000115 00000 n\n0000000266 00000 n\ntrailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n360\n%%%%EOF\n' > "$TEST_PDF"
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
echo ""
info "API: ${API_BASE_URL}"
info "User: ${TEST_USERNAME}"
echo ""

STEP=0
WORKFLOW_START=$(date +%s)

# ── Step 1: Health ────────────────────────────────────────────────────────────
STEP=1
info "[Step $STEP/7] Health check …"
HEALTH_RESP=$(curl -s -w "\n__STATUS__%{http_code}" --max-time 5 \
  "${API_BASE_URL}/health" 2>/dev/null || echo -e "\n__STATUS__000")
HEALTH_STATUS=$(parse_status "$HEALTH_RESP")
[[ "$HEALTH_STATUS" == "200" ]] || step_fail "$STEP" "GET /health returned HTTP $HEALTH_STATUS"
pass "Step $STEP: GET /health → 200"

# ── Step 2: Login ─────────────────────────────────────────────────────────────
STEP=2
info "[Step $STEP/7] Login …"
LOGIN_RESP=$(post_json "${API_BASE_URL}/api/auth/login" \
  "{\"username\":\"${TEST_USERNAME}\",\"password\":\"${TEST_PASSWORD}\"}")
LOGIN_STATUS=$(parse_status "$LOGIN_RESP")
LOGIN_BODY=$(parse_body "$LOGIN_RESP")
[[ "$LOGIN_STATUS" == "200" ]] || step_fail "$STEP" "Login returned HTTP $LOGIN_STATUS"

GW_TOKEN=$(echo "$LOGIN_BODY" | jq -r '.access_token // ""' 2>/dev/null || true)
GW_REFRESH=$(echo "$LOGIN_BODY" | jq -r '.refresh_token // ""' 2>/dev/null || true)
[[ -n "$GW_TOKEN" && "$GW_TOKEN" != "null" ]] || step_fail "$STEP" "No access_token in login response"
pass "Step $STEP: Login successful, token obtained."

# ── Step 3: Upload ────────────────────────────────────────────────────────────
STEP=3
info "[Step $STEP/7] Upload document …"
UPLOAD_RESP=$(curl -s -w "\n__STATUS__%{http_code}" --max-time 30 \
  -H "Authorization: Bearer $GW_TOKEN" \
  -F "file=@${TEST_PDF};type=application/pdf" \
  -F "description=Golden workflow E2E smoke test" \
  -F "tags=golden,smoke,e2e" \
  "${API_BASE_URL}/api/files/upload" 2>/dev/null || echo -e "\n__STATUS__000")
UPLOAD_STATUS=$(parse_status "$UPLOAD_RESP")
UPLOAD_BODY=$(parse_body "$UPLOAD_RESP")
[[ "$UPLOAD_STATUS" == "200" || "$UPLOAD_STATUS" == "201" ]] || \
  step_fail "$STEP" "Upload returned HTTP $UPLOAD_STATUS. Body: $UPLOAD_BODY"

GW_FILE_ID=$(echo "$UPLOAD_BODY" | jq -r '.file_id // ""' 2>/dev/null || true)
[[ -n "$GW_FILE_ID" && "$GW_FILE_ID" != "null" ]] || step_fail "$STEP" "No file_id in upload response"
STORAGE=$(echo "$UPLOAD_BODY" | jq -r '.file_info.storage_backend // "?"' 2>/dev/null || true)
pass "Step $STEP: Upload OK → file_id=${GW_FILE_ID}, backend=${STORAGE}"

# ── Step 4: Submit processing ─────────────────────────────────────────────────
STEP=4
info "[Step $STEP/7] Submit processing job (mode=static) …"
PROCESS_RESP=$(post_json "${API_BASE_URL}/api/files/process" \
  "{\"file_ids\":[\"${GW_FILE_ID}\"],\"mode\":\"static\"}" \
  "$GW_TOKEN")
PROCESS_STATUS=$(parse_status "$PROCESS_RESP")
PROCESS_BODY=$(parse_body "$PROCESS_RESP")
[[ "$PROCESS_STATUS" == "200" || "$PROCESS_STATUS" == "201" || "$PROCESS_STATUS" == "202" ]] || \
  step_fail "$STEP" "Process submit returned HTTP $PROCESS_STATUS. Body: $PROCESS_BODY"

GW_JOB_ID=$(echo "$PROCESS_BODY" | jq -r '.job_id // ""' 2>/dev/null || true)
[[ -n "$GW_JOB_ID" && "$GW_JOB_ID" != "null" ]] || step_fail "$STEP" "No job_id in process response"
INIT_STATUS=$(echo "$PROCESS_BODY" | jq -r '.status // "?"' 2>/dev/null || true)
pass "Step $STEP: Job submitted → job_id=${GW_JOB_ID}, status=${INIT_STATUS}"

# ── Step 5: Poll until completed ─────────────────────────────────────────────
STEP=5
info "[Step $STEP/7] Polling job status (timeout: ${PROCESS_TIMEOUT}s) …"
ELAPSED=0
JOB_DONE=""
while [[ $ELAPSED -lt $PROCESS_TIMEOUT ]]; do
  STATUS_RESP=$(get_auth "${API_BASE_URL}/api/files/process/${GW_JOB_ID}/status" "$GW_TOKEN")
  STATUS_HTTP=$(parse_status "$STATUS_RESP")
  STATUS_BODY=$(parse_body "$STATUS_RESP")

  [[ "$STATUS_HTTP" == "200" ]] || step_fail "$STEP" "Status poll → HTTP $STATUS_HTTP"

  CURRENT=$(echo "$STATUS_BODY" | jq -r '.status // ""' 2>/dev/null || true)
  if [[ "$CURRENT" == "completed" ]]; then
    JOB_DONE="completed"
    break
  elif [[ "$CURRENT" == "failed" ]]; then
    JOB_DONE="failed"
    ERR=$(echo "$STATUS_BODY" | jq -r '.error // .message // "unknown"' 2>/dev/null || echo "unknown")
    step_fail "$STEP" "Job failed: $ERR"
  fi
  info "  [${ELAPSED}s] status: $CURRENT"
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done
[[ "$JOB_DONE" == "completed" ]] || step_fail "$STEP" "Timeout after ${PROCESS_TIMEOUT}s"
pass "Step $STEP: Job completed in ~${ELAPSED}s."

# ── Step 6: Retrieve results ───────────────────────────────────────────────────
STEP=6
info "[Step $STEP/7] Retrieve results …"
RESULTS_RESP=$(get_auth "${API_BASE_URL}/api/files/process/${GW_JOB_ID}/results" "$GW_TOKEN")
RESULTS_HTTP=$(parse_status "$RESULTS_RESP")
RESULTS_BODY=$(parse_body "$RESULTS_RESP")
[[ "$RESULTS_HTTP" == "200" ]] || step_fail "$STEP" "Results → HTTP $RESULTS_HTTP"

if echo "$RESULTS_BODY" | jq . >/dev/null 2>&1; then
  CHARS=${#RESULTS_BODY}
  pass "Step $STEP: Results received (${CHARS} chars of JSON)."
else
  fail "Step $STEP: Results response is not valid JSON: $RESULTS_BODY"
fi

# ── Step 7: Logout ────────────────────────────────────────────────────────────
STEP=7
info "[Step $STEP/7] Logout …"
LOGOUT_RESP=$(post_json "${API_BASE_URL}/api/auth/logout" "{}" "$GW_TOKEN")
LOGOUT_STATUS=$(parse_status "$LOGOUT_RESP")

if [[ "$LOGOUT_STATUS" == "200" || "$LOGOUT_STATUS" == "204" ]]; then
  pass "Step $STEP: Logout → HTTP $LOGOUT_STATUS"
elif [[ "$LOGOUT_STATUS" == "404" ]]; then
  info "Step $STEP: Logout endpoint not present (404). Skipping."
else
  warn "Step $STEP: Logout → HTTP $LOGOUT_STATUS (continuing anyway)."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
WORKFLOW_END=$(date +%s)
TOTAL=$((WORKFLOW_END - WORKFLOW_START))
echo ""
pass "Golden Workflow complete in ${TOTAL}s."
info "  file_id  : $GW_FILE_ID"
info "  job_id   : $GW_JOB_ID"

summarize "Golden Workflow"
