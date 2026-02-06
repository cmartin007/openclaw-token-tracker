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

set -e

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

# Time ranges
TODAY=$(date -u '+%Y-%m-%d')
WEEK_AGO=$(date -u -d "6 days ago" '+%Y-%m-%d')
MONTH_AGO=$(date -u -d "29 days ago" '+%Y-%m-%d')
HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# PHASE 2: HISTORY DIRECTORY SETUP (Bug #4 Fix)
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

# Get pricing for a model
# ⚠️ IMPORTANT: Verify pricing against https://www.anthropic.com/pricing
# Last verified: Feb 6, 2026
get_model_pricing() {
  local MODEL=$1
  case "$MODEL" in
    "claude-haiku-4-5")
      # Input: $1/M, Output: $5/M (verified Feb 2026)
      echo "0.000001|0.000005|Claude Haiku 4.5 (\$1.00/M in, \$5.00/M out)"
      ;;
    "claude-sonnet-4-5")
      # Input: $3/M, Output: $15/M (verified Feb 2026)
      echo "0.000003|0.000015|Claude Sonnet 4.5 (\$3.00/M in, \$15.00/M out)"
      ;;
    "claude-opus-4-6")
      # Input: $5/M (≤200K), Output: $25/M (≤200K) (verified Feb 2026)
      echo "0.000005|0.000025|Claude Opus 4.6 (\$5.00/M in, \$25.00/M out)"
      ;;
    *)
      echo "0.000001|0.000005|Unknown Model - Using Haiku rates (\$1.00/M in, \$5.00/M out) ⚠️ VERIFY at https://www.anthropic.com/pricing"
      ;;
  esac
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
# PHASE 3: GET SESSION DATA WITH VALIDATION (Bug #2 + #3 Fix)
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

# Now safe to extract data
PRIMARY_MODEL=$(echo "$SESSIONS_JSON" | jq -r '.sessions[0].model // "unknown"')
IFS='|' read -r INPUT_COST OUTPUT_COST MODEL_NAME <<< "$(get_model_pricing "$PRIMARY_MODEL")"

# ============================================================================
# PHASE 4: CALCULATE TODAY'S LIVE DATA (Bug #1 Fix: Add // 0 fallback)
# ============================================================================

TODAY_LIVE_INPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .inputTokens // 0] | add // 0')
TODAY_LIVE_OUTPUT=$(echo "$SESSIONS_JSON" | jq '[.sessions[] | .outputTokens // 0] | add // 0')
TODAY_TOKENS=$((TODAY_LIVE_INPUT + TODAY_LIVE_OUTPUT))
TODAY_COST=$(awk "BEGIN {printf \"%.4f\", $TODAY_LIVE_INPUT * $INPUT_COST + $TODAY_LIVE_OUTPUT * $OUTPUT_COST}")

# ============================================================================
# PHASE 5: OUTPUT REPORT
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Token Usage Breakdown"
echo "🤖 Model: ${CYAN}$MODEL_NAME${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# TODAY (live data)
CURRENT_TIME=$(date -u '+%H:%M UTC')
echo "  ${BLUE}TODAY (live @ ${CURRENT_TIME}):${NC}"
printf "    Input:  %10s | Output: %10s | Total: %10s | Cost: ${YELLOW}\$%s${NC}\n" \
  "$TODAY_LIVE_INPUT" "$TODAY_LIVE_OUTPUT" "$TODAY_TOKENS" "$TODAY_COST"

# WEEKLY (last 7 days from history)
show_period_stats "WEEKLY (last 7 days)" "$WEEK_AGO" "$TODAY" "$INPUT_COST" "$OUTPUT_COST"

# MONTHLY (last 30 days from history)
show_period_stats "MONTHLY (last 30 days)" "$MONTH_AGO" "$TODAY" "$INPUT_COST" "$OUTPUT_COST"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 History: $HISTORY_DIR"
echo "✅ Generated by bash (0 tokens)"
