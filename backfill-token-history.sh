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
echo "📊 Fetching all historical usage from Anthropic API (grouped by model)..."

# Backfill from Jan 1, 2025 to today
START_DATE="2025-01-01T00:00:00Z"
END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAGE_TOKEN=""
TOTAL_SAVED=0

while true; do
  # Build query with model grouping
  QUERY="https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&bucket_width=1d&group_by[]=model&limit=31"
  
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
  
  # Parse data for this page - store all results per day
  echo "$RESPONSE" | jq -c '.data[]' 2>/dev/null | while read -r ENTRY; do
    [[ -z "$ENTRY" ]] && continue
    
    TIMESTAMP=$(echo "$ENTRY" | jq -r '.starting_at')
    DATE="${TIMESTAMP%T*}"
    HISTORY_FILE="$HISTORY_DIR/${DATE}.json"
    
    RESULTS=$(echo "$ENTRY" | jq '.results' 2>/dev/null)
    
    # Only save if there are results
    if echo "$RESULTS" | jq -e 'length > 0' > /dev/null 2>&1; then
      # Create or overwrite with all model data for this day
      SNAPSHOT=$(cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$DATE",
  "results": $RESULTS
}
EOF
)
      
      echo "$SNAPSHOT" | jq '.' > "$HISTORY_FILE"
      TOTAL_SAVED=$((TOTAL_SAVED + 1))
    fi
  done
  
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
