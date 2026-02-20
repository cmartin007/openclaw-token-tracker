#!/bin/bash
# daily-token-counter.sh - Token aggregator with persistent historical data
# Reads current sessions + daily snapshots for accurate daily/weekly/monthly breakdown
# Zero Claude tokens. Pure bash + jq.
# 
# BUGFIXES (Feb 6, 2026):
# - Added dependency validation (jq, openclaw)
# - Added JSON response validation
# - Fixed jq null arithmetic bomb with // 0 fallbacks
# - Auto-creates history directory with user feedback
# - MEDIUM PRIORITY FIXES (Feb 6, 2026):
#   - Added cross-platform date support (GNU + BSD)
#   - Added file locking for concurrent safety
#   - Added atomic file writes for history
#   - Added model validation against known list
#   - Added date format validation for history files
# - CONFIGURATION IMPROVEMENTS (Feb 9, 2026):
#   - Externalized pricing to pricing.json config file
#   - Added pricing file validation
#   - Made pricing updates easier (no code changes needed)

set -e

# ============================================================================
# CONCURRENCY SAFETY: File Locking
# ============================================================================

LOCK_FILE="/tmp/token-counter.lock"

# Acquire lock with timeout
acquire_lock() {
  local timeout=10
  local elapsed=0
  
  while [[ $elapsed -lt $timeout ]]; do
    if mkdir "$LOCK_FILE" 2>/dev/null; then
      echo $$ > "$LOCK_FILE/pid"
      return 0
    fi
    sleep 0.5
    ((elapsed++))
  done
  
  echo "❌ Error: Another instance is running (locked for ${timeout}s)"
  exit 1
}

# Release lock
release_lock() {
  rm -rf "$LOCK_FILE" 2>/dev/null || true
}

# Trap to clean up lock on exit
trap release_lock EXIT

# Acquire lock immediately
acquire_lock

# ============================================================================
# PHASE 1: DEPENDENCY VALIDATION (Bug #2 Fix)
# ============================================================================

# Check for required commands
for cmd in jq openclaw; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Error: Required command '$cmd' not found"
    if [ "$cmd" = "jq" ]; then
      echo "   Install: sudo apt install -y jq"
    else
      echo "   Install: https://docs.openclaw.ai/install"
    fi
    exit 1
  fi
done

# Validate OpenClaw is responding
if ! openclaw status &> /dev/null; then
  echo "❌ Error: openclaw CLI found but not responding"
  echo "   Check your OpenClaw installation and configuration"
  echo "   Try: openclaw status --deep"
  exit 1
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING_FILE="${PRICING_FILE:-$SCRIPT_DIR/pricing.json}"

# Time ranges (cross-platform: works on GNU date and BSD date)
TODAY=$(date -u '+%Y-%m-%d')

# Calculate date ranges (works on both GNU and BSD/macOS)
if date -d "1 day" &>/dev/null 2>&1; then
  # GNU date
  WEEK_AGO=$(date -u -d "6 days ago" '+%Y-%m-%d')
  MONTH_START=$(date -u '+%Y-%m-01')  # First day of current month
else
  # BSD date (macOS)
  WEEK_AGO=$(date -u -v-6d '+%Y-%m-%d')
  MONTH_START=$(date -u -v1d '+%Y-%m-01')  # First day of current month
fi

HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# PHASE 2: PRICING FILE VALIDATION
# ============================================================================

# Check if pricing file exists
if [[ ! -f "$PRICING_FILE" ]]; then
  echo "❌ Error: Pricing configuration file not found: $PRICING_FILE"
  echo "   Create it with model pricing data or set PRICING_FILE environment variable"
  echo "   See: https://www.anthropic.com/pricing"
  exit 1
fi

# Validate pricing file is valid JSON
if ! jq -e '.models' "$PRICING_FILE" > /dev/null 2>&1; then
  echo "❌ Error: Invalid pricing configuration file: $PRICING_FILE"
  echo "   File must be valid JSON with a 'models' object"
  exit 1
fi

# ============================================================================
# PHASE 3: HISTORY DIRECTORY SETUP (Bug #4 Fix)
# ============================================================================

# Auto-create history directory if missing
if [[ ! -d "$HISTORY_DIR" ]]; then
  echo "📁 Creating history directory: $HISTORY_DIR"
  mkdir -p "$HISTORY_DIR"
  echo "   Note: Historical data will accumulate from today forward"
  echo ""
fi

# ============================================================================
# FUNCTIONS
# ============================================================================

# Validate and get pricing for a model from pricing.json
# Reads from external config file for easy updates
# Falls back to default pricing if model not found
get_model_pricing() {
  local MODEL=$1
  
  # Try exact match first
  if jq -e ".models.\"$MODEL\"" "$PRICING_FILE" > /dev/null 2>&1; then
    # Found exact match, proceed
    :
  else
    # Try case-insensitive match for MiniMax
    local MODEL_KEY=$(jq -r ".models | to_entries | .[] | select(.key | test(\"^minimax\"; \"i\")) | .key" "$PRICING_FILE" 2>/dev/null | head -1)
    if [[ -n "$MODEL_KEY" && "$MODEL_KEY" != "null" ]]; then
      MODEL="$MODEL_KEY"
    else
      # Fallback: use default MiniMax pricing (very cheap)
      echo "0.0000001|0.0000005|MiniMax (fallback pricing: \$0.10/M in, \$0.50/M out)"
      return 0
    fi
  fi
  
  # Extract pricing data
  local INPUT_COST=$(jq -r ".models.\"$MODEL\".input_cost_per_token" "$PRICING_FILE")
  local OUTPUT_COST=$(jq -r ".models.\"$MODEL\".output_cost_per_token" "$PRICING_FILE")
  local DISPLAY_NAME=$(jq -r ".models.\"$MODEL\".display_name" "$PRICING_FILE")
  
  # Validate extracted data
  if [[ -z "$INPUT_COST" || -z "$OUTPUT_COST" || -z "$DISPLAY_NAME" ]]; then
    echo "0.0000001|0.0000005|MiniMax (fallback pricing: \$0.10/M in, \$0.50/M out)"
    return 0
  fi
  
  # Return in pipe-delimited format (for backward compatibility)
  echo "$INPUT_COST|$OUTPUT_COST|$DISPLAY_NAME"
}

# Sum tokens from history files in a date range
sum_history_tokens() {
  local START_DATE=$1
  local END_DATE=$2
  
  local TOTAL_INPUT=0
  local TOTAL_OUTPUT=0
  
  # Find all history files in range
  for hist_file in "$HISTORY_DIR"/*.json; do
    [ -f "$hist_file" ] || continue
    FILE_DATE=$(basename "$hist_file" .json)
    
    # Validate date format (YYYY-MM-DD) to avoid garbage files
    if ! [[ "$FILE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "⚠️  Warning: Skipping invalid history file (bad date format): $hist_file" >&2
      continue
    fi
    
    # Check if file date is in range
    if [[ "$FILE_DATE" > "$START_DATE" || "$FILE_DATE" == "$START_DATE" ]] && \
       [[ "$FILE_DATE" < "$END_DATE" || "$FILE_DATE" == "$END_DATE" ]]; then
      
      # Validate JSON before parsing (Bug #3 Fix)
      if ! jq -e '.inputTokens' "$hist_file" > /dev/null 2>&1; then
        echo "⚠️  Warning: Corrupted history file: $hist_file (skipping)" >&2
        continue
      fi
      
      FILE_INPUT=$(jq -r '.inputTokens // 0' "$hist_file" 2>/dev/null || echo "0")
      FILE_OUTPUT=$(jq -r '.outputTokens // 0' "$hist_file" 2>/dev/null || echo "0")
      TOTAL_INPUT=$((TOTAL_INPUT + FILE_INPUT))
      TOTAL_OUTPUT=$((TOTAL_OUTPUT + FILE_OUTPUT))
    fi
  done
  
  echo "$TOTAL_INPUT|$TOTAL_OUTPUT"
}

# Display period stats with date ranges
show_period_stats() {
  local PERIOD_NAME=$1
  local START_DATE=$2
  local END_DATE=$3
  local INPUT_COST=$4
  local OUTPUT_COST=$5
  
  IFS='|' read -r PERIOD_INPUT PERIOD_OUTPUT <<< "$(sum_history_tokens "$START_DATE" "$END_DATE")"
  PERIOD_TOKENS=$((PERIOD_INPUT + PERIOD_OUTPUT))
  PERIOD_COST=$(awk "BEGIN {printf \"%.4f\", $PERIOD_INPUT * $INPUT_COST + $PERIOD_OUTPUT * $OUTPUT_COST}")
  
  echo "  ${BLUE}${PERIOD_NAME}${NC} (${START_DATE} to ${END_DATE}):"
  printf "    Input:  %10s | Output: %10s | Total: %10s | Cost: ${YELLOW}\$%s${NC}\n" \
    "$PERIOD_INPUT" "$PERIOD_OUTPUT" "$PERIOD_TOKENS" "$PERIOD_COST"
}

# ============================================================================
# PHASE 4: GET SESSION DATA WITH VALIDATION (Bug #2 + #3 Fix)
# ============================================================================

# Get sessions JSON
SESSIONS_JSON=$(openclaw sessions list --json 2>&1)
GET_EXIT_CODE=$?

# Check if command succeeded
if [[ $GET_EXIT_CODE -ne 0 ]]; then
  echo "❌ Error: Failed to fetch session data from OpenClaw"
  echo "   $SESSIONS_JSON"
  exit 1
fi

# Validate not empty
if [[ -z "$SESSIONS_JSON" ]]; then
  echo "❌ Error: Empty response from OpenClaw"
  exit 1
fi

# Validate JSON structure (Bug #3 Fix)
if ! echo "$SESSIONS_JSON" | jq -e '.sessions' > /dev/null 2>&1; then
  echo "❌ Error: Invalid JSON response from OpenClaw"
  echo "   Expected: {\"sessions\": [...]}"
  echo "   Got: $SESSIONS_JSON"
  exit 1
fi

# Check if sessions array is empty
SESSION_COUNT=$(echo "$SESSIONS_JSON" | jq '.sessions | length')
if [[ $SESSION_COUNT -eq 0 ]]; then
  echo "❌ Error: No active sessions found"
  echo "   OpenClaw needs at least one active session to calculate tokens"
  exit 1
fi

# Now safe to extract data
PRIMARY_MODEL=$(echo "$SESSIONS_JSON" | jq -r '.sessions[0].model // "unknown"')

# Save and restore IFS to avoid breaking parent shell
SAVED_IFS="$IFS"
IFS='|'
PRICING_OUTPUT=$(get_model_pricing "$PRIMARY_MODEL" 2>&1)
MODEL_PRICING_STATUS=$?
read -r INPUT_COST OUTPUT_COST MODEL_NAME <<< "$PRICING_OUTPUT"
IFS="$SAVED_IFS"

# Validate model was recognized and pricing data was parsed
if [[ $MODEL_PRICING_STATUS -ne 0 ]]; then
  echo "❌ Error: Failed to get pricing for model: $PRIMARY_MODEL"
  echo "   (See error details above)"
  exit 1
fi

# Validate parsed pricing data isn't empty
if [[ -z "$INPUT_COST" || -z "$OUTPUT_COST" ]]; then
  echo "❌ Error: Failed to parse pricing data for model: $PRIMARY_MODEL"
  echo "   Input cost: '$INPUT_COST', Output cost: '$OUTPUT_COST'"
  echo "   Check pricing file: $PRICING_FILE"
  exit 1
fi

# ============================================================================
# PHASE 5: CALCULATE TODAY'S CUMULATIVE DATA (since 00:00 UTC)
# ============================================================================

# Get live session data
TODAY_LIVE_INPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .inputTokens // 0] | add // 0')
TODAY_LIVE_OUTPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .outputTokens // 0] | add // 0')

# Validate numeric values
if ! [[ "$TODAY_LIVE_INPUT" =~ ^[0-9]+$ ]]; then
  echo "❌ Error: Invalid input token count: $TODAY_LIVE_INPUT"
  exit 1
fi
if ! [[ "$TODAY_LIVE_OUTPUT" =~ ^[0-9]+$ ]]; then
  echo "❌ Error: Invalid output token count: $TODAY_LIVE_OUTPUT"
  exit 1
fi

# Add historical snapshot from today (if it exists)
TODAY_HISTORY_FILE="$HISTORY_DIR/$TODAY.json"
TODAY_HIST_INPUT=0
TODAY_HIST_OUTPUT=0

if [[ -f "$TODAY_HISTORY_FILE" ]] && jq -e '.inputTokens' "$TODAY_HISTORY_FILE" > /dev/null 2>&1; then
  TODAY_HIST_INPUT=$(jq -r '.inputTokens // 0' "$TODAY_HISTORY_FILE" 2>/dev/null || echo "0")
  TODAY_HIST_OUTPUT=$(jq -r '.outputTokens // 0' "$TODAY_HISTORY_FILE" 2>/dev/null || echo "0")
fi

# Cumulative today = historical snapshot + current live session
TODAY_INPUT=$((TODAY_HIST_INPUT + TODAY_LIVE_INPUT))
TODAY_OUTPUT=$((TODAY_HIST_OUTPUT + TODAY_LIVE_OUTPUT))
TODAY_TOKENS=$((TODAY_INPUT + TODAY_OUTPUT))
TODAY_COST=$(awk "BEGIN {printf \"%.4f\", $TODAY_INPUT * $INPUT_COST + $TODAY_OUTPUT * $OUTPUT_COST}")

# ============================================================================
# PHASE 6: OUTPUT REPORT
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 TOKEN USAGE REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 Model: ${CYAN}${MODEL_NAME}${NC}"
echo ""

# TODAY (cumulative since 00:00 UTC)
CURRENT_TIME=$(date -u '+%H:%M UTC')
echo "┌─ TODAY (since 00:00 UTC, current time ${CURRENT_TIME})"
printf "│  📥 Input:    %8s tokens\n" "$TODAY_INPUT"
printf "│  📤 Output:   %8s tokens\n" "$TODAY_OUTPUT"
printf "│  ━━━━━━━━━━━━━━━━━━━━━\n"
printf "│  💰 Cost:     ${YELLOW}\$%-8s${NC}\n" "$TODAY_COST"
echo "│  (cumulative from 00:00 UTC + live session)"
echo "└────────────────────────────────"
echo ""

# WEEKLY (last 7 days from history + today's cumulative)
SAVED_IFS="$IFS"
IFS='|'
read -r WEEK_INPUT WEEK_OUTPUT <<< "$(sum_history_tokens "$WEEK_AGO" "$TODAY")"
IFS="$SAVED_IFS"
# Add today's cumulative data to weekly (not just live session)
WEEK_INPUT=$((WEEK_INPUT + TODAY_INPUT))
WEEK_OUTPUT=$((WEEK_OUTPUT + TODAY_OUTPUT))
WEEK_TOKENS=$((WEEK_INPUT + WEEK_OUTPUT))
WEEK_COST=$(awk "BEGIN {printf \"%.4f\", $WEEK_INPUT * $INPUT_COST + $WEEK_OUTPUT * $OUTPUT_COST}")
echo "┌─ WEEKLY: since $WEEK_AGO 00:00 UTC"
printf "│  📥 Input:    %8s tokens\n" "$WEEK_INPUT"
printf "│  📤 Output:   %8s tokens\n" "$WEEK_OUTPUT"
printf "│  ━━━━━━━━━━━━━━━━━━━━━\n"
printf "│  💰 Cost:     ${YELLOW}\$%-8s${NC}\n" "$WEEK_COST"
echo "│  (current time: ${CURRENT_TIME})"
echo "└────────────────────────────────"
echo ""

# MONTHLY (current month from history + today's cumulative)
SAVED_IFS="$IFS"
IFS='|'
read -r MONTH_INPUT MONTH_OUTPUT <<< "$(sum_history_tokens "$MONTH_START" "$TODAY")"
IFS="$SAVED_IFS"
# Add today's cumulative data to monthly (not just live session)
MONTH_INPUT=$((MONTH_INPUT + TODAY_INPUT))
MONTH_OUTPUT=$((MONTH_OUTPUT + TODAY_OUTPUT))
MONTH_TOKENS=$((MONTH_INPUT + MONTH_OUTPUT))
MONTH_COST=$(awk "BEGIN {printf \"%.4f\", $MONTH_INPUT * $INPUT_COST + $MONTH_OUTPUT * $OUTPUT_COST}")
echo "┌─ MONTHLY: since $MONTH_START 00:00 UTC"
printf "│  📥 Input:    %8s tokens\n" "$MONTH_INPUT"
printf "│  📤 Output:   %8s tokens\n" "$MONTH_OUTPUT"
printf "│  ━━━━━━━━━━━━━━━━━━━━━\n"
printf "│  💰 Cost:     ${YELLOW}\$%-8s${NC}\n" "$MONTH_COST"
echo "│  (current time: ${CURRENT_TIME})"
echo "└────────────────────────────────"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  COST ESTIMATES - Base pricing only"
echo "   Real costs may vary due to:"
echo "   • Prompt caching (can reduce costs by 90%)"
echo "   • Long context >200K tokens (2x cost increase)"
echo "   • Batch API usage (50% discount)"
echo "   • Tool use overhead (web search, code execution)"
echo ""
echo "   For actual costs, run: ./backfill-token-history.sh"
echo "   Or check: https://console.anthropic.com/settings/billing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Generated by bash (0 tokens) 🐕"
