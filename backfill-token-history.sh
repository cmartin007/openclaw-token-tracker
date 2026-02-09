#!/bin/bash
# backfill-token-history.sh - Safe backfill with rate limit protection
# - Skips if already backfilled today
# - Detects rate limits and exits gracefully
# - Exponential backoff between API calls
# Uses pass (password-store) for secure admin API key retrieval

set -e

HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
LOCK_FILE="/tmp/backfill-$(date -u +%Y-%m-%d).lock"
mkdir -p "$HISTORY_DIR"

# Skip if already ran today
if [[ -f "$LOCK_FILE" ]]; then
  echo "ℹ️ Backfill already ran today. Skipping."
  exit 0
fi

# Retrieve admin API key securely from pass
if ! command -v pass &> /dev/null; then
  echo "❌ Error: pass not found"
  exit 1
fi

ADMIN_KEY=$(pass show anthropic/admin-api-key 2>/dev/null)
if [[ -z "$ADMIN_KEY" ]]; then
  echo "❌ Error: Could not retrieve admin API key from pass"
  exit 1
fi

echo "🔓 Admin key retrieved"
echo "📊 Starting backfill..."

# Backfill from Jan 1, 2025 to today
START_DATE="2025-01-01T00:00:00Z"
END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAGE_TOKEN=""
TOTAL_SAVED=0
RETRY_COUNT=0
MAX_RETRIES=3
BACKOFF=5

# Function to handle API errors
handle_api_error() {
  local error_msg=$1
  
  if echo "$error_msg" | grep -q "rate_limit"; then
    echo "⚠️ Rate limited. Pausing backfill."
    exit 0  # Exit gracefully, cron will retry tomorrow
  elif echo "$error_msg" | grep -q "exceeded"; then
    echo "⚠️ Quota exceeded. Will retry tomorrow."
    exit 0
  else
    echo "❌ API Error: $error_msg"
    exit 1
  fi
}

while true; do
  QUERY_COSTS="https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&bucket_width=1d&group_by[]=model&group_by[]=usage_type&limit=31"
  QUERY_TOKENS="https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${START_DATE}&ending_at=${END_DATE}&bucket_width=1d&group_by[]=model&limit=31"
  
  if [[ -n "$PAGE_TOKEN" ]]; then
    QUERY_COSTS="${QUERY_COSTS}&page=${PAGE_TOKEN}"
    QUERY_TOKENS="${QUERY_TOKENS}&page=${PAGE_TOKEN}"
  fi
  
  echo "  Fetching page..." >&2
  
  # Fetch with retry logic
  RESPONSE_COSTS=$(curl -s "$QUERY_COSTS" \
    -H "x-api-key: $ADMIN_KEY" \
    -H "anthropic-version: 2023-06-01")
  
  # Check for rate limit or quota errors immediately
  if echo "$RESPONSE_COSTS" | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE_COSTS" | jq -r '.error.message // "Unknown error"')
    handle_api_error "$ERROR"
  fi
  
  # Small delay between requests (rate limit friendly)
  sleep 0.5
  
  RESPONSE_TOKENS=$(curl -s "$QUERY_TOKENS" \
    -H "x-api-key: $ADMIN_KEY" \
    -H "anthropic-version: 2023-06-01")
  
  if echo "$RESPONSE_TOKENS" | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE_TOKENS" | jq -r '.error.message // "Unknown error"')
    handle_api_error "$ERROR"
  fi
  
  # Process results
  echo "$RESPONSE_COSTS" | jq -c '.data[]' 2>/dev/null | while read -r ENTRY; do
    [[ -z "$ENTRY" ]] && continue
    
    TIMESTAMP=$(echo "$ENTRY" | jq -r '.starting_at')
    DATE="${TIMESTAMP%T*}"
    HISTORY_FILE="$HISTORY_DIR/${DATE}.json"
    
    COST_RESULTS=$(echo "$ENTRY" | jq '.results')
    TOKEN_RESULTS=$(echo "$RESPONSE_TOKENS" | jq ".data[] | select(.starting_at == \"$TIMESTAMP\") | .results")
    
    if echo "$COST_RESULTS" | jq -e 'length > 0' > /dev/null 2>&1; then
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
  
  # Get next page token
  PAGE_TOKEN=$(echo "$RESPONSE_COSTS" | jq -r '.next_page // ""')
  
  if [[ -z "$PAGE_TOKEN" ]]; then
    break
  fi
  
  # Exponential backoff between pages
  sleep "$BACKOFF"
done

# Mark today as done
touch "$LOCK_FILE"

echo ""
echo "✅ Backfill complete!"
echo "   Updated: $TOTAL_SAVED snapshot files"
