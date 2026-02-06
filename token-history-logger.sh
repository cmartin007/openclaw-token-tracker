#!/bin/bash
# token-history-logger.sh - Daily token usage snapshot logger
# Captures end-of-day session stats and persists to history file
# Pure bash, zero LLM tokens.
#
# BUGFIXES (Feb 6, 2026):
# - Added dependency validation
# - Added JSON response validation
# - Added error handling for file writes
# - Auto-creates history directory

set -e

# ============================================================================
# DEPENDENCY VALIDATION
# ============================================================================

for cmd in jq openclaw; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Error: Required command '$cmd' not found"
    exit 1
  fi
done

if ! openclaw status &> /dev/null; then
  echo "❌ Error: openclaw CLI not responding"
  exit 1
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
TODAY=$(date -u '+%Y-%m-%d')
HISTORY_FILE="$HISTORY_DIR/$TODAY.json"

# Create history directory if it doesn't exist
if [[ ! -d "$HISTORY_DIR" ]]; then
  mkdir -p "$HISTORY_DIR"
  if [[ $? -ne 0 ]]; then
    echo "❌ Error: Failed to create history directory: $HISTORY_DIR"
    exit 1
  fi
fi

# ============================================================================
# GET SESSIONS WITH VALIDATION
# ============================================================================

# Get current session stats
SESSIONS_JSON=$(openclaw sessions list --json 2>&1)
GET_EXIT_CODE=$?

if [[ $GET_EXIT_CODE -ne 0 ]]; then
  echo "❌ Error: Failed to fetch sessions from OpenClaw"
  echo "   $SESSIONS_JSON"
  exit 1
fi

if [[ -z "$SESSIONS_JSON" ]]; then
  echo "❌ Error: Empty response from OpenClaw"
  exit 1
fi

# Validate JSON structure
if ! echo "$SESSIONS_JSON" | jq -e '.sessions' > /dev/null 2>&1; then
  echo "❌ Error: Invalid JSON response from OpenClaw"
  exit 1
fi

# ============================================================================
# CALCULATE TOTALS
# ============================================================================

# Extract model info
PRIMARY_MODEL=$(echo "$SESSIONS_JSON" | jq -r '.sessions[0].model // "unknown"')

# Calculate totals (with fallbacks for empty arrays)
TOTAL_INPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .inputTokens // 0] | add // 0')
TOTAL_OUTPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .outputTokens // 0] | add // 0')
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))

# Create timestamp
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# ============================================================================
# BUILD AND SAVE SNAPSHOT
# ============================================================================

# Build snapshot JSON
SNAPSHOT=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$TODAY",
  "model": "$PRIMARY_MODEL",
  "inputTokens": $TOTAL_INPUT,
  "outputTokens": $TOTAL_OUTPUT,
  "totalTokens": $TOTAL_TOKENS,
  "sessions": $(echo "$SESSIONS_JSON" | jq '[.sessions[] | {key: .key, inputTokens: (.inputTokens // 0), outputTokens: (.outputTokens // 0), totalTokens: .totalTokens}]')
}
EOF
)

# Validate snapshot JSON before writing
if ! echo "$SNAPSHOT" | jq '.' > /dev/null 2>&1; then
  echo "❌ Error: Generated invalid JSON snapshot"
  echo "   Snapshot: $SNAPSHOT"
  exit 1
fi

# Write snapshot (overwrite if already exists for today)
if ! echo "$SNAPSHOT" | jq '.' > "$HISTORY_FILE" 2>/dev/null; then
  echo "❌ Error: Failed to write history file: $HISTORY_FILE"
  exit 1
fi

# ============================================================================
# VERIFY FILE WAS WRITTEN
# ============================================================================

if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "❌ Error: History file was not created: $HISTORY_FILE"
  exit 1
fi

# Verify file has content and is valid JSON
if ! jq -e '.totalTokens' "$HISTORY_FILE" > /dev/null 2>&1; then
  echo "❌ Error: History file is invalid or empty: $HISTORY_FILE"
  exit 1
fi

# ============================================================================
# SUCCESS
# ============================================================================

echo "✅ Snapshot saved: $HISTORY_FILE"
echo "   Timestamp: $TIMESTAMP"
echo "   Model: $PRIMARY_MODEL"
echo "   Input: $TOTAL_INPUT | Output: $TOTAL_OUTPUT | Total: $TOTAL_TOKENS"
