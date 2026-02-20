#!/bin/bash
# tokens-command.sh - Clean token usage summary with table format

TOKEN_HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING_FILE="${PRICING_FILE:-$SCRIPT_DIR/pricing.json}"

# Validate runtime dependencies up front
for cmd in curl jq bc base64; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Error: Required command '$cmd' not found"
    exit 1
  fi
done

# Load .env
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

format_num() {
  local num=$1
  if (( $(echo "$num >= 1000000" | bc -l) )); then
    printf "%.1fM" "$(echo "scale=1; $num / 1000000" | bc)"
  elif (( $(echo "$num >= 1000" | bc -l) )); then
    printf "%.1fK" "$(echo "scale=1; $num / 1000" | bc)"
  else
    printf "%.0f" "$num"
  fi
}

# Get MiniMax plan - show raw percentage from API
PLAN_PCT=0
PLAN_WINDOW=""
PLAN_RESETS_IN=""

if [[ -n "$MINIMAX_API_KEY" ]]; then
  PLAN_RESPONSE=$(curl -s --location 'https://platform.minimax.io/v1/api/openplatform/coding_plan/remains?GroupId=2023224439176434323' \
    --header "Authorization: Bearer $MINIMAX_API_KEY" \
    --header 'Content-Type: application/json' 2>/dev/null)
  
  if echo "$PLAN_RESPONSE" | jq -e '.base_resp.status_code == 0' >/dev/null 2>&1; then
    # API field might be REMAINING, not used - invert the calculation
    API_REMAINS=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].current_interval_usage_count // 0')
    API_TOTAL=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].current_interval_total_count // 0')
    if [[ "$API_REMAINS" =~ ^[0-9]+$ && "$API_TOTAL" =~ ^[0-9]+$ && "$API_TOTAL" -gt 0 ]]; then
      USED_COUNT=$((API_TOTAL - API_REMAINS))
      (( USED_COUNT < 0 )) && USED_COUNT=0
      (( USED_COUNT > API_TOTAL )) && USED_COUNT=$API_TOTAL
      PLAN_PCT=$((USED_COUNT * 100 / API_TOTAL))
    else
      PLAN_PCT=0
    fi
    
    # Get time window
    START_TS=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].start_time')
    END_TS=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].end_time')
    REMAINS_MS=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].remains_time')
    
    # Convert to readable times
    START_SEC=$((START_TS / 1000))
    END_SEC=$((END_TS / 1000))
    START_TIME=$(date -u -d "@$START_SEC" +"%H:%M" 2>/dev/null || date -u -j -f %s "$START_SEC" +"%H:%M")
    END_TIME=$(date -u -d "@$END_SEC" +"%H:%M" 2>/dev/null || date -u -j -f %s "$END_SEC" +"%H:%M")
    
    # Convert remains_time to hours/minutes
    RESETS_SEC=$((REMAINS_MS / 1000))
    RESETS_H=$((RESETS_SEC / 3600))
    RESETS_M=$(((RESETS_SEC % 3600) / 60))
    if [[ $RESETS_H -gt 0 ]]; then
      PLAN_RESETS_IN="${RESETS_H} hr ${RESETS_M} min"
    else
      PLAN_RESETS_IN="${RESETS_M} min"
    fi
    
    PLAN_WINDOW="${START_TIME}-${END_TIME} (UTC)"
  fi
fi

PLAN_REMAINS=$((100 - PLAN_PCT))

# Header
if [[ -n "$PLAN_WINDOW" ]]; then
  echo "💳 MiniMax Coding Plan: $PLAN_PCT% used ($PLAN_REMAINS% remaining) • $PLAN_WINDOW • Resets in $PLAN_RESETS_IN"
else
  echo "💳 MiniMax Coding Plan: $PLAN_PCT% used ($PLAN_REMAINS% remaining)"
fi

# Use only current month JSON files
MONTH_PREFIX=$(date -u +%Y-%m)
json_files=("$TOKEN_HISTORY_DIR"/${MONTH_PREFIX}*.json)

if [[ ! -f "${json_files[0]}" ]]; then
  echo "No historical data found."
  exit 0
fi

# Aggregate by model with FULL cost breakdown (including caching)
MONTH_DATA=$(jq -s '
  [.[] | 
    (if .results and (.results | length) > 0 then 
      .results[] 
    elif .inputTokens then 
      {model: (.model // "MiniMax"), uncached: (.inputTokens // 0), cache_5m: 0, cache_1h: 0, cache_read: 0, output: (.outputTokens // 0)}
    else 
      null 
    end)
  ] | 
  map(select(. != null)) |
  group_by(.model) |
  map({
    model: .[0].model, 
    uncached: (map(.uncached // .uncached_input_tokens // 0) | add),
    cache_5m: (map(.cache_5m // .cache_creation.ephemeral_5m_input_tokens // 0) | add),
    cache_1h: (map(.cache_1h // .cache_creation.ephemeral_1h_input_tokens // 0) | add),
    cache_read: (map(.cache_read // .cache_read_input_tokens // 0) | add),
    output: (map(.output // .output_tokens // 0) | add)
  })
' "${json_files[@]}" 2>/dev/null)

# Calculate totals - sum individual model costs properly
TOTAL_UNCACHED=$(echo "$MONTH_DATA" | jq -r '[.[].uncached] | add')
TOTAL_CACHE_5M=$(echo "$MONTH_DATA" | jq -r '[.[].cache_5m] | add')
TOTAL_CACHE_1H=$(echo "$MONTH_DATA" | jq -r '[.[].cache_1h] | add')
TOTAL_CACHE_READ=$(echo "$MONTH_DATA" | jq -r '[.[].cache_read] | add')
TOTAL_OUTPUT=$(echo "$MONTH_DATA" | jq -r '[.[].output] | add')

TOTAL_TOKENS=$((TOTAL_UNCACHED + TOTAL_CACHE_5M + TOTAL_CACHE_1H + TOTAL_CACHE_READ + TOTAL_OUTPUT))

# Calculate cost by summing all models (using average pricing)
# Will be recalculated properly in the loop below
TOTAL_COST=0

# Track total cost properly
RUNNING_TOTAL=0

echo ""
MONTH_NAME=$(date -u +"%B %Y")
echo "📊 $MONTH_NAME - \$$TOTAL_COST total"
echo ""
echo "| Model        | Uncached | Cache 5m  | Cache Read | Output  | Cost   |"
echo "| ------------ | -------- | --------- | ---------- | ------- | ------ |"

# Process each model with model-specific pricing
for row in $(echo "$MONTH_DATA" | jq -r '.[] | @base64'); do
  model=$(echo "$row" | base64 -d | jq -r '.model')
  uncached=$(echo "$row" | base64 -d | jq -r '.uncached')
  cache_5m=$(echo "$row" | base64 -d | jq -r '.cache_5m')
  cache_1h=$(echo "$row" | base64 -d | jq -r '.cache_1h')
  cache_read=$(echo "$row" | base64 -d | jq -r '.cache_read')
  output=$(echo "$row" | base64 -d | jq -r '.output')
  
  [[ -z "$model" || "$uncached" == "null" ]] && continue
  
  # Calculate tokens
  tokens=$((uncached + cache_5m + cache_1h + cache_read + output))
  [[ $tokens -eq 0 ]] && continue
  
  # Initialize cost for each model
  cost=""
  
  # Get pricing based on model family - MiniMax coding plan has no pay-per-use cost
  case "$model" in
    *minimax*|*MiniMax*)
      cost="included"
      ;;
    *haiku*|*Haiku*)
      input_p="0.000001"; output_p="0.000005"
      ;;
    *sonnet*|*Sonnet*)
      input_p="0.000003"; output_p="0.000015"
      ;;
    *opus*|*Opus*)
      input_p="0.000005"; output_p="0.000025"
      ;;
    *)
      input_p="0.000001"; output_p="0.000005"
      ;;
  esac
  
  # Calculate cost if not MiniMax (which is included in plan)
  # Use awk instead of bc for better handling of large numbers
  if [[ "$cost" != "included" ]]; then
    cost=$(awk -v u="$uncached" -v c5="$cache_5m" -v c1="$cache_1h" -v cr="$cache_read" -v o="$output" -v ip="$input_p" -v op="$output_p" 'BEGIN {
      printf "%.2f", (u * ip) + (c5 * ip * 1.25) + (c1 * ip * 2.0) + (cr * ip * 0.1) + (o * op)
    }')
    # Accumulate total cost (only non-MiniMax)
    RUNNING_TOTAL=$(awk -v rt="$RUNNING_TOTAL" -v c="$cost" 'BEGIN { printf "%.2f", rt + c }')
  fi
  
  # Get short model name with version
  case "$model" in
    *haiku*4-5*|*Haiku*4-5*) short="Haiku 4.5" ;;
    *haiku*4.5*|*Haiku*4.5*) short="Haiku 4.5" ;;
    *haiku*|*Haiku*) short="Haiku" ;;
    *opus*4-5*|*Opus*4-5*) short="Opus 4.5" ;;
    *opus*4.5*|*Opus*4.5*) short="Opus 4.5" ;;
    *opus*|*Opus*) short="Opus" ;;
    *sonnet*4-5*|*Sonnet*4-5*) short="Sonnet 4.5" ;;
    *sonnet*4-20250514*|*Sonnet*4-20250514*) short="Sonnet 4" ;;
    *sonnet*|*Sonnet*) short="Sonnet" ;;
    *minimax*|*MiniMax*) short="MiniMax" ;;
    *) short="$model" ;;
  esac
  
  # Format each token column
  uncached_fmt=$(format_num "$uncached")
  cache_5m_fmt=$(format_num "$cache_5m")
  cache_read_fmt=$(format_num "$cache_read")
  output_fmt=$(format_num "$output")
  
  if [[ "$cost" == "included" ]]; then
    printf "| %-12s | %-8s | %-9s | %-10s | %-7s | %-6s |\n" "$short" "$uncached_fmt" "$cache_5m_fmt" "$cache_read_fmt" "$output_fmt" "$cost"
  else
    printf "| %-12s | %-8s | %-9s | %-10s | %-7s | \$%-6s |\n" "$short" "$uncached_fmt" "$cache_5m_fmt" "$cache_read_fmt" "$output_fmt" "$cost"
  fi
done

TOTAL_FMT=$(format_num "$TOTAL_TOKENS")
# Use accumulated running total instead of rough estimate
TOTAL_COST=${RUNNING_TOTAL:-0}
echo "| ------------ | -------- | --------- | ---------- | ------- | ------ |"
printf "| TOTAL        |          |           |            | %-7s | \$%-6s |\n" "$TOTAL_FMT" "$TOTAL_COST"
echo ""

# Warning
[[ $PLAN_REMAINS -lt 100 ]] && echo "You're almost out of MiniMax prompts - only $PLAN_REMAINS left! 🐕"

exit 0
