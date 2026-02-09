#!/bin/bash
# test-pricing.sh - Test pricing.json configuration
# Run this to verify pricing file is working correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING_FILE="$SCRIPT_DIR/pricing.json"

echo "🧪 Testing pricing configuration..."
echo ""

# Test 1: File exists
echo "Test 1: Checking if pricing.json exists..."
if [[ -f "$PRICING_FILE" ]]; then
  echo "  ✅ Found: $PRICING_FILE"
else
  echo "  ❌ Not found: $PRICING_FILE"
  exit 1
fi
echo ""

# Test 2: Valid JSON
echo "Test 2: Validating JSON syntax..."
if python3 -m json.tool "$PRICING_FILE" > /dev/null 2>&1; then
  echo "  ✅ Valid JSON"
else
  echo "  ❌ Invalid JSON"
  exit 1
fi
echo ""

# Test 3: Has required fields (if jq is available)
if command -v jq &> /dev/null; then
  echo "Test 3: Checking required fields..."
  
  if jq -e '.models' "$PRICING_FILE" > /dev/null 2>&1; then
    echo "  ✅ Has 'models' field"
  else
    echo "  ❌ Missing 'models' field"
    exit 1
  fi
  
  if jq -e '.source' "$PRICING_FILE" > /dev/null 2>&1; then
    echo "  ✅ Has 'source' field"
  else
    echo "  ⚠️  Missing 'source' field (optional)"
  fi
  
  if jq -e '.updated' "$PRICING_FILE" > /dev/null 2>&1; then
    echo "  ✅ Has 'updated' field"
  else
    echo "  ⚠️  Missing 'updated' field (optional)"
  fi
  echo ""
  
  # Test 4: List available models
  echo "Test 4: Available models..."
  jq -r '.models | keys[]' "$PRICING_FILE" | while read -r model; do
    echo "  📦 $model"
    
    # Check each model has required fields
    INPUT_COST=$(jq -r ".models.\"$model\".input_cost_per_token" "$PRICING_FILE")
    OUTPUT_COST=$(jq -r ".models.\"$model\".output_cost_per_token" "$PRICING_FILE")
    DISPLAY_NAME=$(jq -r ".models.\"$model\".display_name" "$PRICING_FILE")
    
    if [[ "$INPUT_COST" == "null" || "$OUTPUT_COST" == "null" || "$DISPLAY_NAME" == "null" ]]; then
      echo "    ❌ Missing required fields for $model"
      exit 1
    else
      echo "    ✅ Input: $INPUT_COST, Output: $OUTPUT_COST"
    fi
  done
  echo ""
  
  # Test 5: Test extracting pricing for a known model
  echo "Test 5: Extracting pricing for claude-haiku-4-5..."
  HAIKU_INPUT=$(jq -r '.models."claude-haiku-4-5".input_cost_per_token' "$PRICING_FILE")
  HAIKU_OUTPUT=$(jq -r '.models."claude-haiku-4-5".output_cost_per_token' "$PRICING_FILE")
  
  if [[ "$HAIKU_INPUT" == "0.000001" && "$HAIKU_OUTPUT" == "0.000005" ]]; then
    echo "  ✅ Correct pricing: \$1.00/M in, \$5.00/M out"
  else
    echo "  ❌ Incorrect pricing: $HAIKU_INPUT, $HAIKU_OUTPUT"
    exit 1
  fi
  echo ""
  
else
  echo "Test 3-5: Skipped (jq not installed)"
  echo "  Install jq for comprehensive testing: sudo apt install jq"
  echo ""
fi

# Test 6: Check pricing file modification date
echo "Test 6: Pricing file metadata..."
UPDATED_DATE=$(python3 -c "import json; print(json.load(open('$PRICING_FILE'))['updated'])" 2>/dev/null || echo "unknown")
echo "  Last verified: $UPDATED_DATE"
echo "  Official source: https://www.anthropic.com/pricing"
echo ""

echo "✅ All tests passed!"
echo ""
echo "Next steps:"
echo "  1. Run ./daily-token-counter.sh to test with real data"
echo "  2. Verify pricing at https://www.anthropic.com/pricing"
echo "  3. Update pricing.json if prices have changed"
