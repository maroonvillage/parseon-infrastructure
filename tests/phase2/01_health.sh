#!/usr/bin/env bash
# =============================================================================
# Phase 2 Check 01: API Health Checks
#
# Verifies:
#   - GET /health        → {"status":"ok","version":"..."}
#   - GET /health/detailed → JSON with system metrics
#   - GET /api/rag/health  → RAG subsystem healthy
#   - Response time acceptable (< 5s)
#
# Requirements: API_BASE_URL set (via run_phase2.sh or exported manually)
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_api_url

section "01 · API Health Checks"

# ── Helper: HTTP GET with status + body ───────────────────────────────────────
http_get() {
  local url="$1"
  local response http_status body start_ms elapsed_ms

  start_ms=$(date +%s%3N 2>/dev/null || date +%s)
  response=$(curl -s -w "\n__STATUS__%{http_code}" \
    --max-time 10 --location "$url" 2>/dev/null || echo -e "\n__STATUS__000")
  end_ms=$(date +%s%3N 2>/dev/null || date +%s)
  elapsed_ms=$(( end_ms - start_ms ))

  http_status=$(echo "$response" | grep -o '__STATUS__[0-9]*' | grep -o '[0-9]*')
  body=$(echo "$response" | sed 's/__STATUS__[0-9]*$//')

  echo "$http_status|$body|$elapsed_ms"
}

# ── 1. GET /health ────────────────────────────────────────────────────────────
info "Checking GET ${API_BASE_URL}/health …"

result=$(http_get "${API_BASE_URL}/health")
STATUS=$(echo "$result" | cut -d'|' -f1)
BODY=$(echo "$result" | cut -d'|' -f2)
MS=$(echo "$result" | cut -d'|' -f3)

if [[ "$STATUS" == "200" ]]; then
  pass "GET /health → HTTP 200"
elif [[ "$STATUS" == "000" ]]; then
  fail "GET /health → connection failed (is the API running and is API_BASE_URL correct?)"
  fail "API_BASE_URL=${API_BASE_URL}"
  summarize "Health"
  exit $?
else
  fail "GET /health → HTTP $STATUS (expected 200)"
fi

# Check response body
API_STATUS=$(echo "$BODY" | jq -r '.status // ""' 2>/dev/null || true)
API_VERSION=$(echo "$BODY" | jq -r '.version // ""' 2>/dev/null || true)

if [[ "$API_STATUS" == "ok" ]]; then
  pass "Response body: status is 'ok'"
else
  fail "Response body: status='${API_STATUS:-missing}' (expected 'ok')  body: $BODY"
fi

if [[ -n "$API_VERSION" && "$API_VERSION" != "null" ]]; then
  pass "Response body: version='$API_VERSION'"
else
  warn "Response body: 'version' field not present (expected per Phase 2 spec)"
fi

if [[ "$MS" -lt 5000 ]]; then
  pass "Response time: ${MS}ms (< 5000ms)"
else
  warn "Response time: ${MS}ms (slow — over 5000ms, may indicate a cold start)"
fi

# ── 2. GET /health/detailed ───────────────────────────────────────────────────
echo ""
info "Checking GET ${API_BASE_URL}/health/detailed …"

result=$(http_get "${API_BASE_URL}/health/detailed")
STATUS=$(echo "$result" | cut -d'|' -f1)
BODY=$(echo "$result" | cut -d'|' -f2)
MS=$(echo "$result" | cut -d'|' -f3)

if [[ "$STATUS" == "200" ]]; then
  pass "GET /health/detailed → HTTP 200"
else
  fail "GET /health/detailed → HTTP $STATUS (expected 200)"
fi

# Verify it returns valid JSON
if echo "$BODY" | jq . &>/dev/null; then
  pass "GET /health/detailed returns valid JSON."
  # Log any top-level keys
  KEYS=$(echo "$BODY" | jq -r 'keys | join(", ")' 2>/dev/null || true)
  info "Response keys: $KEYS"
else
  warn "GET /health/detailed response is not valid JSON."
fi

if [[ "$MS" -lt 5000 ]]; then
  pass "Response time: ${MS}ms"
else
  warn "Response time: ${MS}ms (slow)"
fi

# ── 3. GET /api/rag/health ────────────────────────────────────────────────────
echo ""
info "Checking GET ${API_BASE_URL}/api/rag/health …"

result=$(http_get "${API_BASE_URL}/api/rag/health")
STATUS=$(echo "$result" | cut -d'|' -f1)
BODY=$(echo "$result" | cut -d'|' -f2)

if [[ "$STATUS" == "200" ]]; then
  pass "GET /api/rag/health → HTTP 200"
elif [[ "$STATUS" == "503" ]]; then
  warn "GET /api/rag/health → HTTP 503 (RAG subsystem unavailable — Neo4j or Pinecone may not be reachable)"
else
  fail "GET /api/rag/health → HTTP $STATUS (expected 200)"
fi

if echo "$BODY" | jq . &>/dev/null; then
  RAG_STATUS=$(echo "$BODY" | jq -r '.status // ""' 2>/dev/null || true)
  [[ -n "$RAG_STATUS" ]] && info "RAG health status: $RAG_STATUS"
fi

summarize "Health"
