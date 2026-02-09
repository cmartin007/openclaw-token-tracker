#!/bin/bash
# backfill-token-history.sh - Backfill token usage from Anthropic Admin API
# Uses pass (password-store) for secure admin API key retrieval

set -e

HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
mkdir -p "$HISTORY_DIR"

# Retrieve admin API key securely from pass
if ! command -v pass &> /dev/null; then
  echo "❌ Error: pass not found"
  exit 1
fi

echo "🔓 Retrieving Anthropic Admin API key from pass..."
ADMIN_KEY=$(pass show anthropic/admin-api-key 2>/dev/null)

if [[ -z "$ADMIN_KEY" ]]; then
  echo "❌ Error: Could not retrieve admin API key from pass"
  exit 1
fi

echo "✅ Admin key retrieved securely"
echo ""
echo "📊 Fetching all historical usage from Anthropic API..."

# Backfill from Jan 1, 2025 to today
START_DATE="2025-01-01T00:00:00Z"
END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAGE_TOKEN=""
TOTAL_SAVED=0

while true; do
  # Build query
  QUERY="https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&bucket_width=1d&limit=31"
  
  if [[ -n "$PAGE_TOKEN" ]]; then
    QUERY="${QUERY}&page=${PAGE_TOKEN}"
  fi
  
  echo "  Fetching page..." >&2
  
  # Fetch data
  RESPONSE=$(curl -s "$QUERY" \
    -H "x-api-key: $ADMIN_KEY" \
    -H "anthropic-version: 2023-06-01")
  
  # Check for errors
  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // "Unknown error"')
    echo "❌ API Error: $ERROR"
    exit 1
  fi
  
  # Parse data for this page
  DATES=$(echo "$RESPONSE" | jq -r '.data[] | "\(.starting_at) \(.results[0].uncached_input_tokens // 0) \(.results[0].output_tokens // 0)"' 2>/dev/null)
  
  while read -r LINE; do
    [[ -z "$LINE" ]] && continue
    
    TIMESTAMP=$(echo "$LINE" | awk '{print $1}')
    DATE="${TIMESTAMP%T*}"
    INPUT=$(echo "$LINE" | awk '{print $2}')
    OUTPUT=$(echo "$LINE" | awk '{print $3}')
    TOTAL=$((INPUT + OUTPUT))
    
    # Only save if we have data
    if [[ $TOTAL -gt 0 ]]; then
      HISTORY_FILE="$HISTORY_DIR/${DATE}.json"
      
      # Don't overwrite if already exists (preserve local tracking)
      if [[ ! -f "$HISTORY_FILE" ]]; then
        SNAPSHOT=$(cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$DATE",
  "model": "claude-haiku-4-5",
  "inputTokens": $INPUT,
  "outputTokens": $OUTPUT,
  "totalTokens": $TOTAL,
  "sessions": [
    {
      "key": "backfilled",
      "inputTokens": $INPUT,
      "outputTokens": $OUTPUT,
      "totalTokens": $TOTAL
    }
  ]
}
EOF
)
        
        echo "$SNAPSHOT" | jq '.' > "$HISTORY_FILE"
        TOTAL_SAVED=$((TOTAL_SAVED + 1))
      fi
    fi
  done <<< "$DATES"
  
  # Check for next page
  PAGE_TOKEN=$(echo "$RESPONSE" | jq -r '.next_page // ""')
  
  if [[ -z "$PAGE_TOKEN" ]]; then
    break
  fi
done

echo ""
echo "✅ Backfill complete!"
echo "   Created/updated: $TOTAL_SAVED snapshot files"
echo "   Location: $HISTORY_DIR"
echo ""
echo "📊 Updated token history:"
/home/openclaw/.openclaw/workspace/git-repos/openclaw-token-tracker/tokens-command.sh
