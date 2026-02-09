#!/bin/bash
# backfill-token-history.sh - Backfill token/cost usage from Anthropic Admin API
# Dual query: get costs by usage_type AND tokens by model
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
echo "📊 Fetching all historical usage from Anthropic API (dual query)..."

# Backfill from Jan 1, 2025 to today
START_DATE="2025-01-01T00:00:00Z"
END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAGE_TOKEN=""
TOTAL_SAVED=0

while true; do
  # Query 1: Group by model + usage_type for COSTS
  QUERY_COSTS="https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&bucket_width=1d&group_by[]=model&group_by[]=usage_type&limit=31"
  
  # Query 2: Group by model only for TOKENS
  QUERY_TOKENS="https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&bucket_width=1d&group_by[]=model&limit=31"
  
  if [[ -n "$PAGE_TOKEN" ]]; then
    QUERY_COSTS="${QUERY_COSTS}&page=${PAGE_TOKEN}"
    QUERY_TOKENS="${QUERY_TOKENS}&page=${PAGE_TOKEN}"
  fi
  
  echo "  Fetching page (costs + tokens)..." >&2
  
  # Fetch both
  RESPONSE_COSTS=$(curl -s "$QUERY_COSTS" \
    -H "x-api-key: $ADMIN_KEY" \
    -H "anthropic-version: 2023-06-01")
  
  RESPONSE_TOKENS=$(curl -s "$QUERY_TOKENS" \
    -H "x-api-key: $ADMIN_KEY" \
    -H "anthropic-version: 2023-06-01")
  
  # Check for errors
  if echo "$RESPONSE_COSTS" | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE_COSTS" | jq -r '.error.message // "Unknown error"')
    echo "❌ API Error: $ERROR"
    exit 1
  fi
  
  # Merge and store data
  echo "$RESPONSE_COSTS" | jq -c '.data[]' 2>/dev/null | while read -r ENTRY; do
    [[ -z "$ENTRY" ]] && continue
    
    TIMESTAMP=$(echo "$ENTRY" | jq -r '.starting_at')
    DATE="${TIMESTAMP%T*}"
    HISTORY_FILE="$HISTORY_DIR/${DATE}.json"
    
    # Extract cost results (by usage_type)
    COST_RESULTS=$(echo "$ENTRY" | jq '.results')
    
    # Now get token results for this date from RESPONSE_TOKENS
    TOKEN_RESULTS=$(echo "$RESPONSE_TOKENS" | jq ".data[] | select(.starting_at == \"$TIMESTAMP\") | .results")
    
    if echo "$COST_RESULTS" | jq -e 'length > 0' > /dev/null 2>&1; then
      # Create snapshot with both costs and tokens
      SNAPSHOT=$(cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$DATE",
  "costs": $COST_RESULTS,
  "tokens": $TOKEN_RESULTS
}
EOF
)
      
      echo "$SNAPSHOT" | jq '.' > "$HISTORY_FILE"
      TOTAL_SAVED=$((TOTAL_SAVED + 1))
    fi
  done
  
  # Check for next page
  PAGE_TOKEN=$(echo "$RESPONSE_COSTS" | jq -r '.next_page // ""')
  
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
