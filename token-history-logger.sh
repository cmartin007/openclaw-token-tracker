#!/bin/bash
# token-history-logger.sh - Daily token usage snapshot logger
# Captures end-of-day session stats and persists to history file
# Pure bash, zero LLM tokens.

set -e

HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
TODAY=$(date -u '+%Y-%m-%d')
HISTORY_FILE="$HISTORY_DIR/$TODAY.json"

# Create history directory if it doesn't exist
mkdir -p "$HISTORY_DIR"

# Get current session stats
SESSIONS_JSON=$(openclaw sessions list --json 2>/dev/null)

# Extract model info
PRIMARY_MODEL=$(echo "$SESSIONS_JSON" | jq -r '.sessions[0].model // "unknown"')

# Calculate totals
TOTAL_INPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .inputTokens // 0] | add')
TOTAL_OUTPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .outputTokens // 0] | add')
TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))

# Create timestamp
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Build snapshot JSON
SNAPSHOT=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$TODAY",
  "model": "$PRIMARY_MODEL",
  "inputTokens": $TOTAL_INPUT,
  "outputTokens": $TOTAL_OUTPUT,
  "totalTokens": $TOTAL_TOKENS,
  "sessions": $(echo "$SESSIONS_JSON" | jq '[.sessions[] | {key: .key, inputTokens: .inputTokens, outputTokens: .outputTokens, totalTokens: .totalTokens}]')
}
EOF
)

# Write snapshot (overwrite if already exists for today)
echo "$SNAPSHOT" | jq '.' > "$HISTORY_FILE" 2>/dev/null

echo "✅ Snapshot saved: $HISTORY_FILE"
echo "   Input: $TOTAL_INPUT | Output: $TOTAL_OUTPUT | Total: $TOTAL_TOKENS"
