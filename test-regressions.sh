#!/bin/bash
# test-regressions.sh - Lightweight checks for critical bugfix regressions

set -euo pipefail

pass_count=0

assert_contains() {
  local file=$1
  local pattern=$2
  local description=$3
  if rg -q --fixed-strings "$pattern" "$file"; then
    echo "PASS: $description"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $description"
    echo "  Missing pattern in $file: $pattern"
    exit 1
  fi
}

assert_not_contains() {
  local file=$1
  local pattern=$2
  local description=$3
  if rg -q --fixed-strings "$pattern" "$file"; then
    echo "FAIL: $description"
    echo "  Unexpected pattern in $file: $pattern"
    exit 1
  else
    echo "PASS: $description"
    pass_count=$((pass_count + 1))
  fi
}

assert_contains "daily-token-counter.sh" "sleep 1" "Lock retry cadence matches 1-second elapsed increments"
assert_contains "daily-token-counter.sh" "YESTERDAY=" "Yesterday date is computed for history cutoffs"
assert_contains "daily-token-counter.sh" 'sum_history_tokens "$WEEK_AGO" "$YESTERDAY"' "Weekly history excludes today's snapshot from pre-sum"
assert_contains "daily-token-counter.sh" 'sum_history_tokens "$MONTH_START" "$YESTERDAY"' "Monthly history excludes today's snapshot from pre-sum"
assert_not_contains "daily-token-counter.sh" 'sum_history_tokens "$WEEK_AGO" "$TODAY"' "Weekly pre-sum no longer includes today"
assert_not_contains "daily-token-counter.sh" 'sum_history_tokens "$MONTH_START" "$TODAY"' "Monthly pre-sum no longer includes today"

assert_contains "backfill-token-history.sh" 'done < <(echo "$RESPONSE" | jq -c '\''.data[]'\'' 2>/dev/null)' "Backfill loop runs in parent shell (no pipe subshell)"

assert_contains "tokens-command.sh" "for cmd in curl jq bc base64; do" "Token command validates required dependencies"
assert_contains "tokens-command.sh" "\"\$API_TOTAL\" -gt 0" "Token command guards division against zero totals"

echo ""
echo "All regression checks passed ($pass_count assertions)."
