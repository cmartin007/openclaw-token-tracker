#!/bin/bash
# tokens-command.sh - Clean token usage summary with table format

TOKEN_HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING_FILE="${PRICING_FILE:-$SCRIPT_DIR/pricing.json}"

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
    API_REMAINS=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].current_interval_usage_count')
    API_TOTAL=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].current_interval_total_count')
    # If API count is remaining, then used = total - remaining
    PLAN_PCT=$(echo "scale=0; ($API_TOTAL - $API_REMAINS) * 100 / $API_TOTAL" | bc)
    
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

# Calculate totals with proper cost formula
TOTAL_UNCACHED=$(echo "$MONTH_DATA" | jq -r '[.[].uncached] | add')
TOTAL_CACHE_5M=$(echo "$MONTH_DATA" | jq -r '[.[].cache_5m] | add')
TOTAL_CACHE_1H=$(echo "$MONTH_DATA" | jq -r '[.[].cache_1h] | add')
TOTAL_CACHE_READ=$(echo "$MONTH_DATA" | jq -r '[.[].cache_read] | add')
TOTAL_OUTPUT=$(echo "$MONTH_DATA" | jq -r '[.[].output] | add')

# Default to MiniMax pricing for now (simple estimate)
TOTAL_TOKENS=$((TOTAL_UNCACHED + TOTAL_CACHE_5M + TOTAL_CACHE_1H + TOTAL_CACHE_READ + TOTAL_OUTPUT))
# Rough estimate: $0.0006 per 1M tokens (average)
TOTAL_COST=$(echo "scale=2; $TOTAL_TOKENS * 0.6 / 1000000" | bc 2>/dev/null | sed 's/^\./0./')

echo ""
MONTH_NAME=$(date -u +"%B %Y")
echo "📊 $MONTH_NAME - \$$TOTAL_COST total"
echo ""
echo "| Model  | Tokens | Cost   |"
echo "|--------|--------|--------|"

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
  
  # Get pricing based on model family
  case "$model" in
    *haiku*|*Haiku*)
      input_p="0.000001"; output_p="0.000005"
      ;;
    *sonnet*|*Sonnet*)
      input_p="0.000003"; output_p="0.000015"
      ;;
    *opus*|*Opus*)
      input_p="0.000005"; output_p="0.000025"
      ;;
    *minimax*|*MiniMax*)
      input_p="0.0000001"; output_p="0.0000005"
      ;;
    *)
      input_p="0.000001"; output_p="0.000005"
      ;;
  esac
  
  # Calculate cost: uncached (full) + cache_5m (1.25x) + cache_1h (2x) + cache_read (0.1x) + output (full)
  cost=$(echo "scale=2; 
    ($uncached * $input_p) + 
    ($cache_5m * $input_p * 1.25) + 
    ($cache_1h * $input_p * 2.0) + 
    ($cache_read * $input_p * 0.1) + 
    ($output * $output_p)" | bc 2>/dev/null | sed 's/^\./0./')
  
  short=$(echo "$model" | grep -oE "haiku|sonnet|opus|minimax" | head -1)
  short=$(echo "$short" | sed 's/^./\u&/')
  [[ -z "$short" ]] && short="MiniMax"
  tokens_fmt=$(format_num "$tokens")
  
  printf "| %-6s | %-6s | \$%-6s |\n" "$short" "$tokens_fmt" "$cost"
done

TOTAL_FMT=$(format_num "$TOTAL_TOKENS")
echo "|--------|--------|--------|"
printf "| TOTAL  | %-6s | \$%-6s |\n" "$TOTAL_FMT" "$TOTAL_COST"
echo ""

# Warning
[[ $PLAN_REMAINS -lt 100 ]] && echo "You're almost out of MiniMax prompts - only $PLAN_REMAINS left! 🐕"

exit 0
