# Token Counter Robustness Review

## Issues Found

### 🔴 HIGH PRIORITY

1. **IFS restoration bug**
   - `IFS='|' read -r` is never restored
   - Could break downstream operations if script continues
   - **Fix:** Use subshell: `(IFS='|'; read -r ...)`

2. **Unvalidated arithmetic**
   - `TODAY_LIVE_INPUT` and `TODAY_LIVE_OUTPUT` could be non-numeric
   - If jq returns invalid data, arithmetic fails silently
   - **Fix:** Validate with `[[ $var =~ ^[0-9]+$ ]]`

3. **Empty sessions array handling**
   - Assumes `.sessions[0]` exists
   - If no sessions, PRIMARY_MODEL would be "unknown"
   - Input/output costs would use Haiku rates (wrong!)
   - **Fix:** Check `[ $(echo "$SESSIONS_JSON" | jq '.sessions | length') -gt 0 ]`

### 🟡 MEDIUM PRIORITY

4. **Date arithmetic portability**
   - Uses GNU date: `date -d "6 days ago"`
   - Fails on macOS/BSD (uses BSD date)
   - **Fix:** Use portable date math or `date -u -v-6d` for BSD

5. **Concurrent execution safety**
   - No locking mechanism
   - Two instances could read/write history simultaneously
   - Could produce inconsistent data
   - **Fix:** Use `flock` or pid-based lock file

6. **Partially written history files**
   - No protection against reading files being written
   - Could get corrupted JSON mid-write
   - **Fix:** Write to temp file, then mv atomically

7. **Model detection edge case**
   - If `PRIMARY_MODEL` is wrong, all pricing is wrong
   - No validation that pricing exists for model
   - **Fix:** Validate model against known list before using

8. **History file date format assumption**
   - Assumes `YYYY-MM-DD` format
   - String comparison works but is fragile
   - **Fix:** Validate format with regex

### 🔵 LOW PRIORITY (Nice to Have)

9. **No audit logging**
   - No way to debug when things go wrong
   - Should log errors to file
   - **Fix:** Add optional `--debug` flag with logging

10. **CURRENT_TIME calculated once**
    - If script takes >1 second, time display is stale
    - **Fix:** Calculate at each section or accept minor staleness

11. **No progress indication**
    - Long-running history aggregation has no feedback
    - **Fix:** Add `--verbose` flag with progress messages

12. **No cleanup on partial failure**
    - If output is partially written, data could be corrupted
    - **Fix:** Write to temp, validate, then mv

## Severity Summary

| Issue | Severity | Impact |
|-------|----------|--------|
| IFS restoration | HIGH | Can break parent shell |
| Unvalidated arithmetic | HIGH | Silent failures |
| Empty sessions | MEDIUM | Wrong pricing shown |
| Portability | MEDIUM | Breaks on macOS |
| Concurrency | MEDIUM | Data corruption |
| Partial writes | MEDIUM | Corrupted history |
| Model validation | MEDIUM | Wrong cost calculation |
| Date validation | LOW | Fragile but works |
| Logging | LOW | Hard to debug |
| Time staleness | LOW | Cosmetic |
| Progress | LOW | UX issue |
| Partial output | LOW | Edge case |

## Recommendations

**Short term (do now):**
1. Fix IFS restoration
2. Validate arithmetic inputs
3. Check empty sessions array
4. Add model validation

**Medium term (next update):**
1. Add cross-platform date support
2. Implement file locking
3. Atomic file writes for history
4. Add error logging

**Long term (nice to have):**
1. Progress indication
2. Debug mode
3. Data validation/repair utilities
4. Better error messages

