#!/bin/bash
# tokens-command.sh - Show token usage breakdown by model

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

echo "📊 **Token Usage Breakdown by Model (Last 30 Days)**"
echo ""

# Collect all unique models from last 30 days
MODELS=$(for i in {0..29}; do
  date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
  [[ -f "$date_file" ]] && jq -r '.results[]?.model // empty' "$date_file" 2>/dev/null
done | sort -u)

GRAND_TOTAL_COST=0

for MODEL in $MODELS; do
  [[ -z "$MODEL" ]] && continue
  
  # Get pricing for this model (uncached|cache|output)
  PRICING=$(get_model_pricing "$MODEL")
  UNCACHED_PRICE=$(echo "$PRICING" | cut -d'|' -f1)
  CACHE_PRICE=$(echo "$PRICING" | cut -d'|' -f2)
  OUTPUT_PRICE=$(echo "$PRICING" | cut -d'|' -f3)
  
  # Sum usage for this model over 30 days
  MONTH_U=0
  MONTH_C=0
  MONTH_O=0
  
  for i in {0..29}; do
    date_file="$TOKEN_HISTORY_DIR/$(date -u -d "-$i days" +%Y-%m-%d).json" 2>/dev/null
    if [[ -f "$date_file" ]]; then
      DATA=$(jq ".results[] | select(.model == \"$MODEL\") | {u: .uncached_input_tokens, c: .cache_read_input_tokens, o: .output_tokens}" "$date_file" 2>/dev/null | jq -s 'map({u, c, o}) | {u: map(.u) | add, c: map(.c) | add, o: map(.o) | add}' 2>/dev/null)
      
      if [[ -n "$DATA" && "$DATA" != "null" ]]; then
        U=$(echo "$DATA" | jq '.u // 0')
        C=$(echo "$DATA" | jq '.c // 0')
        O=$(echo "$DATA" | jq '.o // 0')
        MONTH_U=$((MONTH_U + U))
        MONTH_C=$((MONTH_C + C))
        MONTH_O=$((MONTH_O + O))
      fi
    fi
  done
  
  TOTAL=$((MONTH_U + MONTH_C + MONTH_O))
  
  if [[ $TOTAL -gt 0 ]]; then
    U_COST=$(echo "scale=4; $MONTH_U * $UNCACHED_PRICE / 1000000" | bc)
    C_COST=$(echo "scale=4; $MONTH_C * $CACHE_PRICE / 1000000" | bc)
    O_COST=$(echo "scale=4; $MONTH_O * $OUTPUT_PRICE / 1000000" | bc)
    TOTAL_COST=$(echo "scale=4; $U_COST + $C_COST + $O_COST" | bc)
    
    GRAND_TOTAL_COST=$(echo "scale=4; $GRAND_TOTAL_COST + $TOTAL_COST" | bc)
    
    echo "**$MODEL**"
    echo "   Uncached: $MONTH_U @ \$$UNCACHED_PRICE/M = \$$U_COST"
    if [[ $MONTH_C -gt 0 ]]; then
      echo "   Cached:   $MONTH_C @ \$$CACHE_PRICE/M = \$$C_COST"
    fi
    echo "   Output:   $MONTH_O @ \$$OUTPUT_PRICE/M = \$$O_COST"
    echo "   Total: $TOTAL tokens | **\$$TOTAL_COST**"
    echo ""
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💰 **TOTAL COST (Last 30 Days): \$$GRAND_TOTAL_COST**"
echo ""
echo "📁 History stored in: $TOKEN_HISTORY_DIR"
