#!/bin/bash
# tokens-command.sh - Show cost + token breakdown by model

TOKEN_HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"

# Function to format numbers
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

# Function to show breakdown for a time period
show_period_breakdown() {
  local period_name=$1
  local num_days=$2
  
  echo "**$period_name**"
  echo ""
  
  # Collect all unique models from period
  MODELS=$(for i in $(seq 0 $((num_days - 1))); do
    date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
    [[ -f "$date_file" ]] && jq -r '.tokens[]?.model // empty' "$date_file" 2>/dev/null
  done | sort -u)
  
  PERIOD_TOTAL_COST=0
  PERIOD_TOTAL_TOKENS=0
  
  for MODEL in $MODELS; do
    [[ -z "$MODEL" ]] && continue
    
    # Format model name
    MODEL_SHORT=$(echo "$MODEL" | sed 's/Claude //; s/ 4\.[0-9]*//; s/.*\(Haiku\|Sonnet\|Opus\).*/\1/')
    
    # Sum costs by usage type + collect token counts
    NO_CACHE_COST=0
    CACHE_READ_COST=0
    CACHE_WRITE_COST=0
    OUTPUT_COST=0
    MODEL_TOKENS=0
    
    for i in $(seq 0 $((num_days - 1))); do
      date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
      if [[ -f "$date_file" ]]; then
        # Get costs by usage type
        COSTS=$(jq ".costs[] | select(.model == \"$MODEL\") | {usage_type, cost_usd}" "$date_file" 2>/dev/null)
        while read -r line; do
          [[ -z "$line" ]] && continue
          USAGE_TYPE=$(echo "$line" | jq -r '.usage_type')
          COST=$(echo "$line" | jq '.cost_usd')
          
          case "$USAGE_TYPE" in
            input_no_cache)
              NO_CACHE_COST=$(echo "$NO_CACHE_COST + $COST" | bc)
              ;;
            input_cache_read)
              CACHE_READ_COST=$(echo "$CACHE_READ_COST + $COST" | bc)
              ;;
            input_cache_write*)
              CACHE_WRITE_COST=$(echo "$CACHE_WRITE_COST + $COST" | bc)
              ;;
            output)
              OUTPUT_COST=$(echo "$OUTPUT_COST + $COST" | bc)
              ;;
          esac
        done < <(echo "$COSTS" | jq -c '.')
        
        # Get token counts
        TOKENS=$(jq ".tokens[] | select(.model == \"$MODEL\") | .uncached_input_tokens + .cache_read_input_tokens + .output_tokens" "$date_file" 2>/dev/null)
        while read -r line; do
          [[ -z "$line" ]] && continue
          MODEL_TOKENS=$(echo "$MODEL_TOKENS + $line" | bc)
        done < <(echo "$TOKENS")
      fi
    done
    
    TOTAL_COST=$(echo "$NO_CACHE_COST + $CACHE_READ_COST + $CACHE_WRITE_COST + $OUTPUT_COST" | bc)
    
    if (( $(echo "$TOTAL_COST > 0 || $MODEL_TOKENS > 0" | bc -l) )); then
      PERIOD_TOTAL_COST=$(echo "$PERIOD_TOTAL_COST + $TOTAL_COST" | bc)
      PERIOD_TOTAL_TOKENS=$((PERIOD_TOTAL_TOKENS + MODEL_TOKENS))
      
      echo "   **$MODEL_SHORT** | $(format_num $MODEL_TOKENS) tokens | **\$$(printf "%.2f" "$TOTAL_COST")**"
      if (( $(echo "$NO_CACHE_COST > 0" | bc -l) )); then
        echo "      📥 Input (no cache): \$$(printf "%.2f" "$NO_CACHE_COST")"
      fi
      if (( $(echo "$CACHE_READ_COST > 0" | bc -l) )); then
        echo "      💾 Input (cache read): \$$(printf "%.2f" "$CACHE_READ_COST")"
      fi
      if (( $(echo "$CACHE_WRITE_COST > 0" | bc -l) )); then
        echo "      📝 Input (cache write): \$$(printf "%.2f" "$CACHE_WRITE_COST")"
      fi
      if (( $(echo "$OUTPUT_COST > 0" | bc -l) )); then
        echo "      📤 Output: \$$(printf "%.2f" "$OUTPUT_COST")"
      fi
      echo ""
    fi
  done
  
  echo "   **SUBTOTAL: $(format_num $PERIOD_TOTAL_TOKENS) tokens | \$$(printf "%.2f" "$PERIOD_TOTAL_COST")**"
  echo ""
}

echo "💰 **Cost & Token Breakdown by Model**"
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
