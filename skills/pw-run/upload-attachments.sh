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
#   - trace.zip (300KB-50MB)        -> blows the Read cap, eats tokens
#   - video.webm (1-100MB)          -> same problem, much worse
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
# Exits 0 on 2xx, prints { id, storage_url, scope } to stdout as JSON.
# Exits 1 with stderr error otherwise.

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

# base64 piped through tr is portable across mac (-i flag) and linux (-w0).
B64=$(base64 < "$FILE" | tr -d '\n')

PAYLOAD=$(mktemp)
trap 'rm -f "$PAYLOAD" /tmp/upload-attachments.resp' EXIT

{
  echo -n '{'
  echo -n "\"project_id\":\"$PROJECT_ID\","
  echo -n "\"file_name\":\"$NAME\","
  echo -n "\"content_type\":\"$CONTENT_TYPE\","
  echo -n "\"content\":\"$B64\""
  [[ -n "$RUN_ID" ]]           && echo -n ",\"run_id\":\"$RUN_ID\""
  [[ -n "$RUN_CASE_ID" ]]      && echo -n ",\"run_case_id\":\"$RUN_CASE_ID\""
  [[ -n "$RUN_CASE_STEP_ID" ]] && echo -n ",\"run_case_step_id\":\"$RUN_CASE_STEP_ID\""
  [[ -n "$STEP_ID" ]]          && echo -n ",\"step_id\":\"$STEP_ID\""
  echo '}'
} > "$PAYLOAD"

URL="${BASE_URL%/}/api/projects/${PROJECT_ID}/attachments:upload"

HTTP_CODE=$(curl -sS -o /tmp/upload-attachments.resp -w "%{http_code}" \
  -X POST "$URL" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary "@$PAYLOAD")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "[upload-attachments] HTTP $HTTP_CODE for $URL" >&2
  cat /tmp/upload-attachments.resp >&2
  echo >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  ID=$(jq -r '.attachment.id // .id // empty' /tmp/upload-attachments.resp)
  STORAGE_URL=$(jq -r '.attachment.storage_url // .storage_url // empty' /tmp/upload-attachments.resp)
else
  ID=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' /tmp/upload-attachments.resp | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  STORAGE_URL=$(grep -oE '"storage_url"[[:space:]]*:[[:space:]]*"[^"]+"' /tmp/upload-attachments.resp | head -1 | sed 's/.*"storage_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

printf '{"id":"%s","storage_url":"%s","scope":"%s","file_name":"%s","content_type":"%s","bytes":%d}\n' \
  "$ID" "$STORAGE_URL" "$SCOPE" "$NAME" "$CONTENT_TYPE" "$(wc -c < "$FILE")"
