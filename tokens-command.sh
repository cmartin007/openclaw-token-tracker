#!/bin/bash
# tokens-command.sh - Show cost breakdown by model and usage type

TOKEN_HISTORY_DIR="/home/openclaw/.openclaw/workspace/token-history"

# Function to format numbers
format_num() {
  local num=$1
  if (( $(echo "$num >= 1" | bc -l) )); then
    printf "%.2f" "$num"
  else
    printf "%.4f" "$num"
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
    [[ -f "$date_file" ]] && jq -r '.results[]?.model // empty' "$date_file" 2>/dev/null
  done | sort -u)
  
  PERIOD_TOTAL_COST=0
  
  for MODEL in $MODELS; do
    [[ -z "$MODEL" ]] && continue
    
    # Format model name for display
    MODEL_SHORT=$(echo "$MODEL" | sed 's/Claude //; s/ 4\.[0-9]*//; s/.*\(Haiku\|Sonnet\|Opus\).*/\1/')
    
    # Sum costs by usage type for this model over period
    NO_CACHE_COST=0
    CACHE_READ_COST=0
    CACHE_WRITE_COST=0
    OUTPUT_COST=0
    
    for i in $(seq 0 $((num_days - 1))); do
      date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
      if [[ -f "$date_file" ]]; then
        # Sum costs by usage type
        COSTS=$(jq ".results[] | select(.model == \"$MODEL\") | {no_cache: (select(.usage_type == \"input_no_cache\") | .cost_usd), cache_read: (select(.usage_type == \"input_cache_read\") | .cost_usd), cache_write: (select(.usage_type | contains(\"cache_write\")) | .cost_usd), output: (select(.usage_type == \"output\") | .cost_usd)}" "$date_file" 2>/dev/null)
        
        while read -r line; do
          [[ -z "$line" ]] && continue
          NC=$(echo "$line" | jq '.no_cache // 0')
          CR=$(echo "$line" | jq '.cache_read // 0')
          CW=$(echo "$line" | jq '.cache_write // 0')
          OUT=$(echo "$line" | jq '.output // 0')
          
          NO_CACHE_COST=$(echo "$NO_CACHE_COST + $NC" | bc)
          CACHE_READ_COST=$(echo "$CACHE_READ_COST + $CR" | bc)
          CACHE_WRITE_COST=$(echo "$CACHE_WRITE_COST + $CW" | bc)
          OUTPUT_COST=$(echo "$OUTPUT_COST + $OUT" | bc)
        done < <(echo "$COSTS" | jq -s '.')
      fi
    done
    
    TOTAL_COST=$(echo "$NO_CACHE_COST + $CACHE_READ_COST + $CACHE_WRITE_COST + $OUTPUT_COST" | bc)
    
    if (( $(echo "$TOTAL_COST > 0" | bc -l) )); then
      PERIOD_TOTAL_COST=$(echo "$PERIOD_TOTAL_COST + $TOTAL_COST" | bc)
      
      echo "   **$MODEL_SHORT** | **\$$(format_num $TOTAL_COST)**"
      if (( $(echo "$NO_CACHE_COST > 0" | bc -l) )); then
        echo "      📥 Input (no cache): \$$(format_num $NO_CACHE_COST)"
      fi
      if (( $(echo "$CACHE_READ_COST > 0" | bc -l) )); then
        echo "      💾 Input (cache read): \$$(format_num $CACHE_READ_COST)"
      fi
      if (( $(echo "$CACHE_WRITE_COST > 0" | bc -l) )); then
        echo "      📝 Input (cache write): \$$(format_num $CACHE_WRITE_COST)"
      fi
      if (( $(echo "$OUTPUT_COST > 0" | bc -l) )); then
        echo "      📤 Output: \$$(format_num $OUTPUT_COST)"
      fi
      echo ""
    fi
  done
  
  echo "   **SUBTOTAL: \$$(format_num $PERIOD_TOTAL_COST)**"
  echo ""
}

echo "💰 **Cost Breakdown by Model**"
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
