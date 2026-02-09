#!/bin/bash
# tokens-command.sh - Show token usage breakdown by model with multiple time periods

TOKEN_HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"

# Model pricing (Anthropic Feb 2026)
get_model_pricing() {
  local model=$1
  case "$model" in
    *haiku*)
      echo "1.00|0.20|5.00"
      ;;
    *sonnet*)
      echo "3.00|0.60|15.00"
      ;;
    *opus*)
      echo "15.00|3.00|75.00"
      ;;
    *)
      echo "1.00|0.20|5.00"  # default to Haiku
      ;;
  esac
}

# Function to show breakdown for a time period
show_period_breakdown() {
  local period_name=$1
  local num_days=$2
  
  echo "**$period_name**"
  echo ""
  
  # Collect all unique models from period
  MODELS=$(for i in $(seq 0 $((num_days - 1))); do
    date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
    [[ -f "$date_file" ]] && jq -r '.results[]?.model // empty' "$date_file" 2>/dev/null
  done | sort -u)
  
  PERIOD_TOTAL_COST=0
  
  for MODEL in $MODELS; do
    [[ -z "$MODEL" ]] && continue
    
    # Get pricing for this model (uncached|cache|output)
    PRICING=$(get_model_pricing "$MODEL")
    UNCACHED_PRICE=$(echo "$PRICING" | cut -d'|' -f1)
    CACHE_PRICE=$(echo "$PRICING" | cut -d'|' -f2)
    OUTPUT_PRICE=$(echo "$PRICING" | cut -d'|' -f3)
    
    # Sum usage for this model over period
    PERIOD_U=0
    PERIOD_C=0
    PERIOD_O=0
    
    for i in $(seq 0 $((num_days - 1))); do
      date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
      if [[ -f "$date_file" ]]; then
        DATA=$(jq ".results[] | select(.model == \"$MODEL\") | {u: .uncached_input_tokens, c: .cache_read_input_tokens, o: .output_tokens}" "$date_file" 2>/dev/null | jq -s 'map({u, c, o}) | {u: map(.u) | add, c: map(.c) | add, o: map(.o) | add}' 2>/dev/null)
        
        if [[ -n "$DATA" && "$DATA" != "null" ]]; then
          U=$(echo "$DATA" | jq '.u // 0')
          C=$(echo "$DATA" | jq '.c // 0')
          O=$(echo "$DATA" | jq '.o // 0')
          PERIOD_U=$((PERIOD_U + U))
          PERIOD_C=$((PERIOD_C + C))
          PERIOD_O=$((PERIOD_O + O))
        fi
      fi
    done
    
    TOTAL=$((PERIOD_U + PERIOD_C + PERIOD_O))
    
    if [[ $TOTAL -gt 0 ]]; then
      U_COST=$(echo "scale=4; $PERIOD_U * $UNCACHED_PRICE / 1000000" | bc)
      C_COST=$(echo "scale=4; $PERIOD_C * $CACHE_PRICE / 1000000" | bc)
      O_COST=$(echo "scale=4; $PERIOD_O * $OUTPUT_PRICE / 1000000" | bc)
      TOTAL_COST=$(echo "scale=4; $U_COST + $C_COST + $O_COST" | bc)
      
      PERIOD_TOTAL_COST=$(echo "scale=4; $PERIOD_TOTAL_COST + $TOTAL_COST" | bc)
      
      echo "   **$MODEL**"
      echo "      📥 Uncached: $PERIOD_U tokens (\$$U_COST)"
      if [[ $PERIOD_C -gt 0 ]]; then
        echo "      💾 Cached: $PERIOD_C tokens (\$$C_COST)"
      fi
      echo "      📤 Output: $PERIOD_O tokens (\$$O_COST)"
      echo "      💰 **\$$TOTAL_COST**"
      echo ""
    fi
  done
  
  echo "   **Subtotal: \$$PERIOD_TOTAL_COST**"
  echo ""
}

echo "📊 **Token Usage Breakdown by Model**"
echo ""

# Last 7 days
show_period_breakdown "📅 Last 7 Days" 7

# This month (Feb 1 - today)
MONTH_START=$(date -u +%Y)-02-01
TODAY=$(date -u +%Y-%m-%d)
DAYS_IN_MONTH=$(( ($(date -u -d "$TODAY" +%s) - $(date -u -d "$MONTH_START" +%s)) / 86400 + 1 ))
show_period_breakdown "📅 This Month (Feb)" $DAYS_IN_MONTH

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 History: $TOKEN_HISTORY_DIR"
