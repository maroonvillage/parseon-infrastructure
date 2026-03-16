#!/usr/bin/env bash
# =============================================================================
# Phase 2 Check 02: Authentication
#
# Verifies:
#   - POST /api/auth/login returns access_token + refresh_token
#   - GET  /api/auth/me returns correct user with valid token
#   - POST /api/auth/verify accepts the token
#   - POST /api/auth/refresh issues a new access_token
#   - Bad credentials return 401
#   - Missing token on protected endpoint returns 401
#
# Side effect: writes access_token to $TOKEN_FILE for use by downstream scripts.
#
# Requirements:
#   - API_BASE_URL set
#   - TEST_USERNAME and TEST_PASSWORD set
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_api_url

section "02 · Authentication"

# ── Prerequisite: credentials must be set ─────────────────────────────────────
if [[ -z "$TEST_USERNAME" || -z "$TEST_PASSWORD" ]]; then
  fail "TEST_USERNAME and TEST_PASSWORD must be set before running auth tests."
  fail "  export TEST_USERNAME=smoketest TEST_PASSWORD=yourpassword"
  summarize "Auth"
  exit $?
fi

info "Testing auth as user: $TEST_USERNAME"

# ── Helper ────────────────────────────────────────────────────────────────────
http_post_json() {
  local url="$1"
  local payload="$2"
  local auth_header="${3:-}"
  local args=(-s -w "\n__STATUS__%{http_code}" --max-time 10
    -H "Content-Type: application/json"
    -d "$payload")
  [[ -n "$auth_header" ]] && args+=(-H "Authorization: $auth_header")
  curl "${args[@]}" "$url" 2>/dev/null || echo -e "\n__STATUS__000"
}

http_get_auth() {
  local url="$1"
  local token="${2:-}"
  local args=(-s -w "\n__STATUS__%{http_code}" --max-time 10)
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  curl "${args[@]}" "$url" 2>/dev/null || echo -e "\n__STATUS__000"
}

parse_status() { echo "$1" | grep -o '__STATUS__[0-9]*' | grep -o '[0-9]*'; }
parse_body()   { echo "$1" | sed 's/__STATUS__[0-9]*$//'; }

# ── 1. Login ─────────────────────────────────────────────────────────────────
info "POST /api/auth/login …"
LOGIN_PAYLOAD="{\"username\":\"${TEST_USERNAME}\",\"password\":\"${TEST_PASSWORD}\"}"
RESPONSE=$(http_post_json "${API_BASE_URL}/api/auth/login" "$LOGIN_PAYLOAD")
STATUS=$(parse_status "$RESPONSE")
BODY=$(parse_body "$RESPONSE")

if [[ "$STATUS" == "200" ]]; then
  pass "POST /api/auth/login → HTTP 200"
elif [[ "$STATUS" == "000" ]]; then
  fail "POST /api/auth/login → connection failed. Check API_BASE_URL=${API_BASE_URL}"
  summarize "Auth"
  exit $?
elif [[ "$STATUS" == "401" ]]; then
  fail "POST /api/auth/login → 401 Unauthorized. Check TEST_USERNAME / TEST_PASSWORD."
  summarize "Auth"
  exit $?
else
  fail "POST /api/auth/login → HTTP $STATUS. Body: $BODY"
  summarize "Auth"
  exit $?
fi

ACCESS_TOKEN=$(echo "$BODY" | jq -r '.access_token // ""' 2>/dev/null || true)
REFRESH_TOKEN=$(echo "$BODY" | jq -r '.refresh_token // ""' 2>/dev/null || true)
TOKEN_TYPE=$(echo "$BODY" | jq -r '.token_type // ""' 2>/dev/null || true)

if [[ -n "$ACCESS_TOKEN" && "$ACCESS_TOKEN" != "null" ]]; then
  pass "access_token returned."
else
  fail "access_token missing from login response. Body: $BODY"
  summarize "Auth"
  exit $?
fi

if [[ -n "$REFRESH_TOKEN" && "$REFRESH_TOKEN" != "null" ]]; then
  pass "refresh_token returned."
else
  warn "refresh_token missing from login response."
fi

if [[ "$TOKEN_TYPE" == "bearer" ]]; then
  pass "token_type is 'bearer'."
else
  warn "token_type is '${TOKEN_TYPE}' (expected 'bearer')."
fi

# Write token to file for downstream scripts
echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
# Store refresh token alongside
echo "$REFRESH_TOKEN" > "${TOKEN_FILE}.refresh"
info "Token cached to $TOKEN_FILE"

# ── 2. GET /api/auth/me ───────────────────────────────────────────────────────
echo ""
info "GET /api/auth/me …"
RESPONSE=$(http_get_auth "${API_BASE_URL}/api/auth/me" "$ACCESS_TOKEN")
STATUS=$(parse_status "$RESPONSE")
BODY=$(parse_body "$RESPONSE")

if [[ "$STATUS" == "200" ]]; then
  pass "GET /api/auth/me → HTTP 200"
  RETURNED_USER=$(echo "$BODY" | jq -r '.username // ""' 2>/dev/null || true)
  if [[ "$RETURNED_USER" == "$TEST_USERNAME" ]]; then
    pass "Returned username matches: $RETURNED_USER"
  else
    fail "Returned username '${RETURNED_USER}' does not match TEST_USERNAME '${TEST_USERNAME}'."
  fi
else
  fail "GET /api/auth/me → HTTP $STATUS (expected 200). Body: $BODY"
fi

# ── 3. POST /api/auth/verify ──────────────────────────────────────────────────
echo ""
info "POST /api/auth/verify …"
RESPONSE=$(http_post_json "${API_BASE_URL}/api/auth/verify" "{}" "Bearer $ACCESS_TOKEN")
STATUS=$(parse_status "$RESPONSE")

if [[ "$STATUS" == "200" ]]; then
  pass "POST /api/auth/verify → HTTP 200 (token is valid)."
else
  fail "POST /api/auth/verify → HTTP $STATUS (expected 200)."
fi

# ── 4. POST /api/auth/refresh ─────────────────────────────────────────────────
if [[ -n "$REFRESH_TOKEN" && "$REFRESH_TOKEN" != "null" ]]; then
  echo ""
  info "POST /api/auth/refresh …"
  REFRESH_PAYLOAD="{\"refresh_token\":\"${REFRESH_TOKEN}\"}"
  RESPONSE=$(http_post_json "${API_BASE_URL}/api/auth/refresh" "$REFRESH_PAYLOAD")
  STATUS=$(parse_status "$RESPONSE")
  BODY=$(parse_body "$RESPONSE")

  if [[ "$STATUS" == "200" ]]; then
    NEW_TOKEN=$(echo "$BODY" | jq -r '.access_token // ""' 2>/dev/null || true)
    if [[ -n "$NEW_TOKEN" && "$NEW_TOKEN" != "null" ]]; then
      pass "POST /api/auth/refresh → new access_token issued."
      # Update the cached token to the refreshed one
      echo "$NEW_TOKEN" > "$TOKEN_FILE"
    else
      fail "POST /api/auth/refresh → 200 but no access_token in response."
    fi
  else
    fail "POST /api/auth/refresh → HTTP $STATUS (expected 200)."
  fi
fi

# ── 5. Negative: bad credentials → 401 ────────────────────────────────────────
echo ""
info "Testing rejection of bad credentials …"
BAD_RESPONSE=$(http_post_json "${API_BASE_URL}/api/auth/login" \
  '{"username":"nouser_smoke","password":"definitelywrong"}')
BAD_STATUS=$(parse_status "$BAD_RESPONSE")

if [[ "$BAD_STATUS" == "401" || "$BAD_STATUS" == "403" ]]; then
  pass "Bad credentials correctly rejected → HTTP $BAD_STATUS."
else
  fail "Bad credentials returned HTTP $BAD_STATUS (expected 401)."
fi

# ── 6. Negative: missing token on protected endpoint → 401 ────────────────────
echo ""
info "Testing rejection of missing token …"
NO_AUTH_RESPONSE=$(http_get_auth "${API_BASE_URL}/api/auth/me")
NO_AUTH_STATUS=$(parse_status "$NO_AUTH_RESPONSE")

if [[ "$NO_AUTH_STATUS" == "401" || "$NO_AUTH_STATUS" == "403" ]]; then
  pass "Missing token correctly rejected on protected endpoint → HTTP $NO_AUTH_STATUS."
else
  fail "Missing token returned HTTP $NO_AUTH_STATUS (expected 401)."
fi

summarize "Auth"
