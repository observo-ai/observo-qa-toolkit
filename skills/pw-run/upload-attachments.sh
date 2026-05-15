#!/usr/bin/env bash
# upload-attachments.sh — Companion helper for the pw-run skill.
#
# WHY THIS EXISTS
# ---------------
# mcp__observo__upload_attachment takes base64-encoded content as a JSON
# string argument. Anything that has to pass through Claude's tool-call
# boundary (Read tool has a 256KB cap on file content) is constrained:
#   - results.json (a few KB)       -> fine via MCP
#   - small screenshots (~10-50 KB) -> fine via MCP
#   - 50-190KB raw                  -> works but expensive (~85K tokens)
#   - > ~190KB raw                  -> IMPOSSIBLE via MCP (Read cap)
# This script does the upload directly via REST + curl, using an API key,
# so large artefacts never round-trip through the model's context.
#
# USAGE
# -----
#   ./upload-attachments.sh --file <path> --project-id <uuid> \
#       [--run-id <uuid|run_key>]      \
#       [--run-case-id <uuid|CODE-N>]  \
#       [--run-case-step-id <uuid>]    \
#       [--step-id <uuid|step_number>] \
#       [--name <override>]            \
#       [--content-type <mime>]        \
#       [--base-url <url>]             \
#       [--api-key <token>]
#
# At least one of run-id / run-case-id / run-case-step-id / step-id is
# required (same contract as the MCP wrapper). API base URL falls back to
# OBSERVO_API_BASE_URL then API_BASE_URL; api key to OBSERVO_API_KEY then
# E2E_ACCOUNT_API_KEY. content-type auto-detected from extension when
# omitted.
#
# Exits 0 on 2xx, prints { id, storage_url, scope, file_name, content_type,
# bytes } JSON to stdout. Exits 1 with stderr error otherwise.

set -euo pipefail

FILE=""
PROJECT_ID=""
RUN_ID=""
RUN_CASE_ID=""
RUN_CASE_STEP_ID=""
STEP_ID=""
NAME_OVERRIDE=""
CONTENT_TYPE=""
BASE_URL="${OBSERVO_API_BASE_URL:-${API_BASE_URL:-}}"
API_KEY="${OBSERVO_API_KEY:-${E2E_ACCOUNT_API_KEY:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)              FILE="$2"; shift 2 ;;
    --project-id)        PROJECT_ID="$2"; shift 2 ;;
    --run-id)            RUN_ID="$2"; shift 2 ;;
    --run-case-id)       RUN_CASE_ID="$2"; shift 2 ;;
    --run-case-step-id)  RUN_CASE_STEP_ID="$2"; shift 2 ;;
    --step-id)           STEP_ID="$2"; shift 2 ;;
    --name)              NAME_OVERRIDE="$2"; shift 2 ;;
    --content-type)      CONTENT_TYPE="$2"; shift 2 ;;
    --base-url)          BASE_URL="$2"; shift 2 ;;
    --api-key)           API_KEY="$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# USAGE/,/^# Exits/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

err() { echo "[upload-attachments] $*" >&2; exit 1; }

[[ -n "$FILE" ]]       || err "--file is required"
[[ -f "$FILE" ]]       || err "--file path does not exist: $FILE"
[[ -n "$PROJECT_ID" ]] || err "--project-id is required"
[[ -n "$BASE_URL" ]]   || err "--base-url required (or set OBSERVO_API_BASE_URL / API_BASE_URL)"
[[ -n "$API_KEY" ]]    || err "--api-key required (or set OBSERVO_API_KEY / E2E_ACCOUNT_API_KEY)"

if [[ -z "$RUN_ID$RUN_CASE_ID$RUN_CASE_STEP_ID$STEP_ID" ]]; then
  err "at least one of --run-id, --run-case-id, --run-case-step-id, --step-id must be set"
fi

NAME="${NAME_OVERRIDE:-$(basename "$FILE")}"

if [[ -z "$CONTENT_TYPE" ]]; then
  case "${NAME##*.}" in
    png)      CONTENT_TYPE="image/png" ;;
    jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
    gif)      CONTENT_TYPE="image/gif" ;;
    webp)     CONTENT_TYPE="image/webp" ;;
    zip)      CONTENT_TYPE="application/zip" ;;
    json)     CONTENT_TYPE="application/json" ;;
    webm)     CONTENT_TYPE="video/webm" ;;
    mp4)      CONTENT_TYPE="video/mp4" ;;
    html|htm) CONTENT_TYPE="text/html" ;;
    txt|log)  CONTENT_TYPE="text/plain" ;;
    *)        CONTENT_TYPE="application/octet-stream" ;;
  esac
fi

if [[ -n "$RUN_CASE_STEP_ID" || -n "$STEP_ID" ]]; then
  SCOPE="step"
elif [[ -n "$RUN_CASE_ID" ]]; then
  SCOPE="run_case"
elif [[ -n "$RUN_ID" ]]; then
  SCOPE="run"
else
  SCOPE="unknown"
fi

# json_escape: escapes the two JSON-significant chars (\, ") in argument
# values. Our domain (UUIDs, short codes, MIME types, file names, presigned
# URLs) doesn't produce control chars or unicode, so this is sufficient.
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# mktemp for BOTH payload AND response. Parallel invocations (e.g. one loop
# uploading trace.zip + video.webm + screenshot for a single failed case)
# would otherwise clobber each other's response file.
PAYLOAD=$(mktemp -t upload-att-payload.XXXXXX)
RESP=$(mktemp -t upload-att-resp.XXXXXX)
trap 'rm -f "$PAYLOAD" "$RESP"' EXIT

# Stream-build the JSON payload to keep base64 out of shell heap.
#
# A naive `B64=$(base64 < "$FILE" | tr -d '\n')` stores the entire base64
# string (×1.333 of file size) in a bash variable. For a 100MB video that's
# ~133MB of heap; on a small CI container the shell can be OOM-killed before
# the script ever reaches curl. The append-to-file pattern below avoids the
# variable entirely — base64 streams straight into $PAYLOAD.
{
  printf '{"project_id":"%s","file_name":"%s","content_type":"%s","content":"' \
    "$(json_escape "$PROJECT_ID")" \
    "$(json_escape "$NAME")" \
    "$(json_escape "$CONTENT_TYPE")"
  base64 < "$FILE" | tr -d '\n'
  printf '"'
  [[ -n "$RUN_ID" ]]           && printf ',"run_id":"%s"' "$(json_escape "$RUN_ID")"
  [[ -n "$RUN_CASE_ID" ]]      && printf ',"run_case_id":"%s"' "$(json_escape "$RUN_CASE_ID")"
  [[ -n "$RUN_CASE_STEP_ID" ]] && printf ',"run_case_step_id":"%s"' "$(json_escape "$RUN_CASE_STEP_ID")"
  [[ -n "$STEP_ID" ]]          && printf ',"step_id":"%s"' "$(json_escape "$STEP_ID")"
  printf '}\n'
} > "$PAYLOAD"

URL="${BASE_URL%/}/api/projects/${PROJECT_ID}/attachments:upload"

HTTP_CODE=$(curl -sS -o "$RESP" -w "%{http_code}" \
  -X POST "$URL" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary "@$PAYLOAD")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "[upload-attachments] HTTP $HTTP_CODE for $URL" >&2
  cat "$RESP" >&2
  echo >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  ID=$(jq -r '.attachment.id // .id // empty' "$RESP")
  STORAGE_URL=$(jq -r '.attachment.storage_url // .storage_url // empty' "$RESP")
else
  ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' "$RESP" | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  STORAGE_URL=$(grep -oE '"storage_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$RESP" | head -1 | sed 's/.*"storage_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# Fail loudly when extraction returns empty. The fallback grep + sed can
# silently produce an empty string if the response shape shifts, and a
# default `{"id":"",...}` output is valid JSON but downstream-useless.
[[ -n "$ID" ]] || err "failed to extract attachment id from response — body was: $(cat "$RESP")"

BYTES=$(wc -c < "$FILE" | tr -d ' ')

# Emit JSON via jq when available — handles all escaping correctly.
# Fallback uses json_escape on every field; same safety contract.
if command -v jq >/dev/null 2>&1; then
  jq -cn \
    --arg id "$ID" \
    --arg storage_url "$STORAGE_URL" \
    --arg scope "$SCOPE" \
    --arg file_name "$NAME" \
    --arg content_type "$CONTENT_TYPE" \
    --argjson bytes "$BYTES" \
    '{id:$id, storage_url:$storage_url, scope:$scope, file_name:$file_name, content_type:$content_type, bytes:$bytes}'
else
  printf '{"id":"%s","storage_url":"%s","scope":"%s","file_name":"%s","content_type":"%s","bytes":%d}\n' \
    "$(json_escape "$ID")" \
    "$(json_escape "$STORAGE_URL")" \
    "$(json_escape "$SCOPE")" \
    "$(json_escape "$NAME")" \
    "$(json_escape "$CONTENT_TYPE")" \
    "$BYTES"
fi
