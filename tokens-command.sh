#!/bin/bash
# tokens-command.sh - Show cost + token breakdown by model with caching info

set -e

TOKEN_HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING_FILE="${PRICING_FILE:-$SCRIPT_DIR/pricing.json}"

# Load .env file if it exists
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  source "$SCRIPT_DIR/.env"
fi

if [[ ! -f "$PRICING_FILE" ]]; then
  echo "❌ Error: Pricing file not found: $PRICING_FILE"
  exit 1
fi

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

# Check MiniMax coding plan balance (if API key available)
if [[ -n "$MINIMAX_API_KEY" ]]; then
  echo "💳 **MiniMax Coding Plan**"
  echo ""
  PLAN_RESPONSE=$(curl -s --location 'https://platform.minimax.io/v1/api/openplatform/coding_plan/remains' \
    --header "Authorization: Bearer $MINIMAX_API_KEY" \
    --header 'Content-Type: application/json' 2>/dev/null)
  
  # Check if response is HTML (Cloudflare block) vs JSON
  if echo "$PLAN_RESPONSE" | grep -q "<!DOCTYPE html"; then
    echo "   ⚠️  API blocked by Cloudflare (server IP restricted)"
    echo "   Run locally or check via https://platform.minimax.io"
  elif echo "$PLAN_RESPONSE" | jq -e '.base_resp.status_code == 0' >/dev/null 2>&1; then
    TOTAL=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].current_interval_total_count')
    USAGE=$(echo "$PLAN_RESPONSE" | jq -r '.model_remains[0].current_interval_usage_count')
    REMAINS=$((TOTAL - USAGE))
    echo "   Remaining: $REMAINS / $TOTAL prompts"
    echo "   Used: $USAGE ($((USAGE * 100 / TOTAL))%)"
  else
    ERROR_MSG=$(echo "$PLAN_RESPONSE" | jq -r '.msg // .message // "Unknown error"' 2>/dev/null)
    echo "   ❌ Error checking plan: $ERROR_MSG"
  fi
  echo ""
fi

show_period_breakdown() {
  local period_name=$1
  local num_days=$2
  
  echo "**$period_name**"
  echo ""
  
  # Collect all JSON files in the period (as array for proper expansion)
  local -a json_files_array
  for i in $(seq 0 $((num_days - 1))); do
    local date_str=$(date -u -d "-$i days" +%Y-%m-%d 2>/dev/null || date -u -v-${i}d +%Y-%m-%d)
    local date_file="$TOKEN_HISTORY_DIR/$date_str.json"
    
    if [[ -f "$date_file" ]]; then
      json_files_array+=("$date_file")
    fi
  done
  
  if [[ ${#json_files_array[@]} -eq 0 ]]; then
    echo "   *No data available*"
    echo ""
    return
  fi
  
  # Create temp files for tracking totals
  local tmp_data=$(mktemp)
  local tmp_costs=$(mktemp)
  local tmp_tokens=$(mktemp)
  local tmp_savings=$(mktemp)
  
  # Extract and aggregate data by model (use -c for compact output, one JSON per line)
  jq -c -s '
    [.[] | .results[]?] |
    group_by(.model) |
    map({
      model: .[0].model,
      uncached_input: (map(.uncached_input_tokens // 0) | add),
      cache_5m: (map(.cache_creation.ephemeral_5m_input_tokens // 0) | add),
      cache_1h: (map(.cache_creation.ephemeral_1h_input_tokens // 0) | add),
      cache_read: (map(.cache_read_input_tokens // 0) | add),
      output: (map(.output_tokens // 0) | add)
    }) |
    sort_by((.uncached_input + .cache_5m + .cache_1h + .cache_read + .output)) | reverse | .[]
  ' "${json_files_array[@]}" 2>/dev/null > "$tmp_data"
  
  # Process each model
  while read -r line; do
    model=$(echo "$line" | jq -r '.model')
    uncached=$(echo "$line" | jq '.uncached_input')
    cache_5m=$(echo "$line" | jq '.cache_5m')
    cache_1h=$(echo "$line" | jq '.cache_1h')
    cache_read=$(echo "$line" | jq '.cache_read')
    output=$(echo "$line" | jq '.output')
    
    [[ -z "$model" || "$model" == "null" ]] && continue
    
    # Get pricing
    base_model=$(echo "$model" | sed 's/-[0-9]\{8\}$//')
    input_price=$(jq -r ".models.\"$base_model\".input_cost_per_token // \"\"" "$PRICING_FILE" 2>/dev/null)
    output_price=$(jq -r ".models.\"$base_model\".output_cost_per_token // \"\"" "$PRICING_FILE" 2>/dev/null)
    
    if [[ -z "$input_price" ]]; then
      continue
    fi
    
    # Calculate costs
    uncached_cost=$(echo "scale=6; $uncached * $input_price" | bc)
    cache_5m_cost=$(echo "scale=6; $cache_5m * $input_price * 1.25" | bc)
    cache_1h_cost=$(echo "scale=6; $cache_1h * $input_price * 2.0" | bc)
    cache_read_cost=$(echo "scale=6; $cache_read * $input_price * 0.1" | bc)
    output_cost=$(echo "scale=6; $output * $output_price" | bc)
    
    actual_cost=$(echo "scale=6; $uncached_cost + $cache_5m_cost + $cache_1h_cost + $cache_read_cost + $output_cost" | bc)
    
    # Cost without caching (all input at base rate)
    total_input=$((uncached + cache_5m + cache_1h + cache_read))
    no_cache_cost=$(echo "scale=6; $total_input * $input_price + $output_cost" | bc)
    savings=$(echo "scale=6; $no_cache_cost - $actual_cost" | bc)
    
    total_tokens=$((uncached + cache_5m + cache_1h + cache_read + output))
    
    # Extract model family
    short_name=$(echo "$model" | grep -oE "haiku|sonnet|opus" | head -1 | sed 's/.*/\u&/')
    
    # Output line: show actual cost only
    printf "   %-10s  %12s tokens  $%.2f\n" "$short_name" "$(format_num $total_tokens)" "$actual_cost"
    printf "   %-10s  %s\n" "" "$model"
    
    # Show INPUT vs OUTPUT clearly with cache breakdown
    total_input=$((uncached + cache_5m + cache_1h + cache_read))
    printf "      INPUT: %s [%s cached↓90%% | %s write | %s raw]  OUTPUT: %s\n" \
      "$(format_num $total_input)" "$(format_num $cache_read)" "$(format_num $((cache_5m + cache_1h)))" "$(format_num $uncached)" "$(format_num $output)"
    echo ""
    
    # Store for totals
    echo "$actual_cost" >> "$tmp_costs"
    echo "$total_tokens" >> "$tmp_tokens"
    echo "$savings" >> "$tmp_savings"
    
  done < "$tmp_data"
  
  # Print totals
  if [[ -s "$tmp_costs" ]]; then
    total_cost=$(awk '{s+=$1} END {printf "%.2f", s}' "$tmp_costs")
    total_tokens=$(awk '{s+=$1} END {print s}' "$tmp_tokens")
    
    if (( $(echo "$total_cost > 0" | bc -l) )); then
      printf "   %-10s  %12s tokens  $%.2f\n" "TOTAL" "$(format_num $total_tokens)" "$total_cost"
    fi
  fi
  
  rm -f "$tmp_data" "$tmp_costs" "$tmp_tokens" "$tmp_savings"
  
  echo ""
}

echo "💰 **Token Usage & Cost Breakdown**"
echo ""

show_period_breakdown "📅 Last 7 Days (rolling)" 7

# Current month: from 1st of current month to today
MONTH_START=$(date -u +%Y-%m-01)
TODAY=$(date -u +%Y-%m-%d)
DAYS_IN_MONTH=$(( ($(date -u -d "$TODAY" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$TODAY" +%s) - $(date -u -d "$MONTH_START" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$MONTH_START" +%s)) / 86400 + 1 ))
MONTH_NAME=$(date -u -d "$MONTH_START" +%B 2>/dev/null || date -u -j -f %Y-%m-%d "$MONTH_START" +%B)
show_period_breakdown "📅 Current Month ($MONTH_NAME 1-today)" $DAYS_IN_MONTH

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Data: $TOKEN_HISTORY_DIR"
echo ""
echo "**Column meanings:**"
echo "  • **Model name & version:** Which Claude model was used"
echo "  • **Tokens:** Total input + output tokens"
echo "  • **Cost:** What you actually paid (includes all pricing modifiers: caching, cache creation, output)"
echo ""
echo "**Token breakdown (INPUT | OUTPUT):**"
echo "  • cached↓90%: Cache read tokens (90% discount applied)"
echo "  • write: Cache creation tokens (1.25x-2.0x overhead to create cache)"
echo "  • raw: Uncached input tokens (full base price)"
