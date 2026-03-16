#!/usr/bin/env bash
# =============================================================================
# Phase 2 Check 03: File Upload
#
# Verifies:
#   - A test PDF can be uploaded via POST /api/files/upload
#   - Response contains file_id and storage_backend == "s3"
#   - GET /api/files/{file_id} returns file metadata
#   - The file actually exists in S3 (via aws s3api head-object)
#   - Upload without auth token returns 401
#
# Side effects:
#   - Creates tests/fixtures/test_document.pdf (if absent)
#   - Writes file_id to ${TOKEN_FILE}.file_id for downstream scripts
#
# Requirements:
#   - API_BASE_URL set
#   - TOKEN_FILE populated by 02_auth.sh
#   - AWS CLI configured with access to S3_DOC_BUCKET
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)/tests"
source "$SCRIPT_DIR/config.sh"
require_api_url

section "03 · File Upload"

# ── Token ─────────────────────────────────────────────────────────────────────
TOKEN=$(read_token)
if [[ -z "$TOKEN" ]]; then
  fail "No auth token found. Run 02_auth.sh first (or set TOKEN_FILE)."
  summarize "Upload"
  exit $?
fi

# ── Ensure test fixture exists ────────────────────────────────────────────────
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_PDF="$FIXTURES_DIR/test_document.pdf"

if [[ ! -f "$TEST_PDF" ]]; then
  info "Creating minimal test PDF at $TEST_PDF …"
  mkdir -p "$FIXTURES_DIR"
  # Minimal valid PDF (1 page, simple text)
  printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]\n/Contents 4 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>\nendobj\n4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 12 Tf 100 750 Td (Parseon Smoke Test) Tj ET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000115 00000 n\n0000000266 00000 n\ntrailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n360\n%%%%EOF\n' > "$TEST_PDF"
  if [[ -f "$TEST_PDF" ]]; then
    pass "Test PDF created: $TEST_PDF ($(wc -c < "$TEST_PDF" | tr -d ' ') bytes)"
  else
    fail "Could not create test PDF at $TEST_PDF"
    summarize "Upload"
    exit $?
  fi
else
  info "Using existing test PDF: $TEST_PDF"
fi

# ── Helper ────────────────────────────────────────────────────────────────────
parse_status() { echo "$1" | grep -oE '__STATUS__[0-9]+' | tail -1 | grep -oE '[0-9]+'; }
parse_body()   { echo "$1" | grep -v '__STATUS__'; }

# ── 1. Upload without auth → 401 ─────────────────────────────────────────────
info "Testing upload without auth token (expect 401) …"
NO_AUTH_RESP=$(curl -s -w "\n__STATUS__%{http_code}" \
  --max-time 15 \
  -F "file=@${TEST_PDF};type=application/pdf" \
  -F "description=smoke test unauthorized" \
  "${API_BASE_URL}/api/files/upload" 2>/dev/null)
NO_AUTH_STATUS=$(parse_status "$NO_AUTH_RESP")

if [[ "$NO_AUTH_STATUS" == "401" || "$NO_AUTH_STATUS" == "403" ]]; then
  pass "Upload without auth → HTTP $NO_AUTH_STATUS (correctly rejected)."
elif [[ "$NO_AUTH_STATUS" == "000" ]]; then
  fail "Upload check: connection failed. Check API_BASE_URL=${API_BASE_URL}"
  summarize "Upload"
  exit $?
else
  fail "Upload without auth → HTTP $NO_AUTH_STATUS (expected 401/403)."
fi

# ── 2. Authenticated upload ────────────────────────────────────────────────
echo ""
info "POST /api/files/upload …"
UPLOAD_RESP=$(curl -s -w "\n__STATUS__%{http_code}" \
  --max-time 30 \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@${TEST_PDF};type=application/pdf" \
  -F "description=Parseon Phase 2 smoke test document" \
  -F "tags=smoke,test,phase2" \
  "${API_BASE_URL}/api/files/upload" 2>/dev/null)
UPLOAD_STATUS=$(parse_status "$UPLOAD_RESP")
UPLOAD_BODY=$(parse_body "$UPLOAD_RESP")

if [[ "$UPLOAD_STATUS" == "200" || "$UPLOAD_STATUS" == "201" ]]; then
  pass "POST /api/files/upload → HTTP $UPLOAD_STATUS"
else
  fail "POST /api/files/upload → HTTP $UPLOAD_STATUS. Body: $UPLOAD_BODY"
  summarize "Upload"
  exit $?
fi

FILE_ID=$(echo "$UPLOAD_BODY" | jq -r '.file_id // ""' 2>/dev/null || true)
STORAGE_BACKEND=$(echo "$UPLOAD_BODY" | jq -r '.file_info.storage_backend // ""' 2>/dev/null || true)
PROCESSING_READY=$(echo "$UPLOAD_BODY" | jq -r '.processing_ready // ""' 2>/dev/null || true)

if [[ -n "$FILE_ID" && "$FILE_ID" != "null" ]]; then
  pass "file_id returned: $FILE_ID"
else
  fail "file_id missing from upload response. Body: $UPLOAD_BODY"
  summarize "Upload"
  exit $?
fi

if [[ "$STORAGE_BACKEND" == "s3" ]]; then
  pass "storage_backend is 's3'."
else
  warn "storage_backend is '${STORAGE_BACKEND}' (expected 's3')."
fi

if [[ "$PROCESSING_READY" == "true" ]]; then
  pass "processing_ready: true"
else
  warn "processing_ready: ${PROCESSING_READY}"
fi

# Persist for downstream scripts
echo "$FILE_ID" > "${TOKEN_FILE}.file_id"
info "file_id cached to ${TOKEN_FILE}.file_id"

# ── 3. GET /api/files/{file_id} ───────────────────────────────────────────────
echo ""
info "GET /api/files/${FILE_ID} …"
GET_RESP=$(curl -s -w "\n__STATUS__%{http_code}" \
  --max-time 10 \
  -H "Authorization: Bearer $TOKEN" \
  "${API_BASE_URL}/api/files/${FILE_ID}" 2>/dev/null)
GET_STATUS=$(parse_status "$GET_RESP")
GET_BODY=$(parse_body "$GET_RESP")

if [[ "$GET_STATUS" == "200" ]]; then
  pass "GET /api/files/${FILE_ID} → HTTP 200"
  RETURNED_ID=$(echo "$GET_BODY" | jq -r '.file_id // ""' 2>/dev/null || true)
  if [[ "$RETURNED_ID" == "$FILE_ID" ]]; then
    pass "Returned file_id matches."
  else
    fail "Returned file_id '${RETURNED_ID}' does not match '${FILE_ID}'."
  fi
elif [[ "$GET_STATUS" == "404" ]]; then
  warn "GET /api/files/${FILE_ID} → 404. File metadata endpoint may not exist."
else
  fail "GET /api/files/${FILE_ID} → HTTP $GET_STATUS. Body: $GET_BODY"
fi

# ── 4. Verify S3 object exists ────────────────────────────────────────────────
echo ""
info "Verifying file exists in S3 bucket ${S3_DOC_BUCKET} …"

if ! command -v aws >/dev/null 2>&1; then
  warn "AWS CLI not found, skipping S3 object verification."
else
  # Common key prefixes to try: documents/<file_id>, uploads/<file_id>, <file_id>
  S3_FOUND=""
  for KEY_PREFIX in "documents/${FILE_ID}" "uploads/${FILE_ID}" "${FILE_ID}"; do
    HEAD_OUT=$(aws s3api head-object \
      --bucket "$S3_DOC_BUCKET" \
      --key "$KEY_PREFIX" \
      --no-cli-pager 2>&1) || true
    if echo "$HEAD_OUT" | grep -q "ContentLength\|Last-Modified\|ETag"; then
      pass "S3 object found at s3://${S3_DOC_BUCKET}/${KEY_PREFIX}"
      S3_FOUND="$KEY_PREFIX"
      break
    fi
    # Try with .pdf suffix
    HEAD_OUT=$(aws s3api head-object \
      --bucket "$S3_DOC_BUCKET" \
      --key "${KEY_PREFIX}.pdf" \
      --no-cli-pager 2>&1) || true
    if echo "$HEAD_OUT" | grep -q "ContentLength\|Last-Modified\|ETag"; then
      pass "S3 object found at s3://${S3_DOC_BUCKET}/${KEY_PREFIX}.pdf"
      S3_FOUND="${KEY_PREFIX}.pdf"
      break
    fi
  done

  if [[ -z "$S3_FOUND" ]]; then
    # Fall back to listing: list objects with prefix matching file_id
    LIST_OUT=$(aws s3api list-objects-v2 \
      --bucket "$S3_DOC_BUCKET" \
      --prefix "$FILE_ID" \
      --max-items 5 \
      --no-cli-pager 2>/dev/null || true)
    KEY_COUNT=$(echo "$LIST_OUT" | jq -r '.KeyCount // 0' 2>/dev/null || echo "0")
    if [[ "$KEY_COUNT" -gt 0 ]]; then
      FOUND_KEY=$(echo "$LIST_OUT" | jq -r '.Contents[0].Key // ""' 2>/dev/null || true)
      pass "S3 object found via listing: s3://${S3_DOC_BUCKET}/${FOUND_KEY}"
    else
      warn "Could not locate S3 object for file_id=${FILE_ID} in ${S3_DOC_BUCKET}."
      warn "The file may use a different key structure. Check the bucket manually."
    fi
  fi
fi

summarize "Upload"
