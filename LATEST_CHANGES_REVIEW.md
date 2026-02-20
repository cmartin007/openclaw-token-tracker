# Review of Latest Changes (Feb 2026)

**Review date:** February 2026  
**Commits reviewed:** `ede96d1` → `d2538be` (last ~10 commits)  
**Branch:** master (clean working tree)

---

## Executive Summary

The project has evolved from a **Claude-only token tracker** into a **multi-provider tracker** with:

1. **MiniMax integration** – Coding plan balance, API-based usage, and display
2. **Unified /tokens display** – Current-month only, cache-aware costs, model table
3. **Mixed history format support** – Both legacy (inputTokens/outputTokens) and API (results with cache breakdown) JSON shapes
4. **Pricing expansion** – MiniMax models in `pricing.json`, cache multipliers, and fallback logic in the counter

**Overall:** Changes are coherent and production-oriented. A few robustness and doc updates are recommended below.

---

## Commit Summary (Newest First)

| Commit    | Date       | Summary |
|-----------|------------|--------|
| `d2538be` | 2026-02-20 | Fix /tokens: current month only, MiniMax time window, reset countdown, % fix |
| `f746a91` | —          | Support mixed token history formats (legacy + API results) |
| `6a4bcb2` | —          | MiniMax coding plan time window and reset info |
| `4a550ed` | —          | Fix MiniMax coding plan API endpoint |
| `956ba7b` | —          | MiniMax coding plan balance check + security (.env, .gitignore) |
| `ec2ec0a` | —          | Update backfill & tokens-command for new API + clean display |
| `f54d739` | —          | Pricing updates |
| `1cc36d8` | —          | Updated pricing logic |

---

## 1. MiniMax Integration

### What Was Added

- **Coding plan API** – `tokens-command.sh` calls MiniMax `coding_plan/remains` with `GroupId=2023224439176434323`.
- **Display** – Plan usage % (used/remaining), optional time window (e.g. `05:00-10:00 (UTC)`), and “Resets in X hr Y min”.
- **Security** – API key from env only; `.env` and `.env.local` in `.gitignore`; `.env.example` documents `MINIMAX_API_KEY`.

### Code Notes

**Percentage calculation (d2538be fix):**

```bash
# API provides current_interval_usage_count (used) and current_interval_total_count
PLAN_PCT=$(echo "scale=0; ($API_TOTAL - $API_REMAINS) * 100 / $API_TOTAL" | bc)
```

Commit message says “inverted” was fixed; the code now treats `current_interval_usage_count` as “used” and derives percent from (total − remains) if needed. Worth confirming with MiniMax docs that `current_interval_usage_count` is “used” (not “remaining”) so the sign is correct.

**Date portability (GNU vs BSD):**

```bash
START_TIME=$(date -u -d "@$START_SEC" +"%H:%M" 2>/dev/null || date -u -j -f %s "$START_SEC" +"%H:%M")
```

GNU tried first, then BSD fallback – good. On some BSD/macOS, `-u` with `-j -f` can be fussy; if you see wrong times on macOS, test the fallback in isolation.

**Hardcoded GroupId:**  
`GroupId=2023224439176434323` is in the script. Consider `MINIMAX_GROUP_ID` in `.env` if multiple groups are possible.

---

## 2. /tokens Display and Token History

### Current-Month-Only Filter

```bash
MONTH_PREFIX=$(date -u +%Y-%m)
json_files=("$TOKEN_HISTORY_DIR"/${MONTH_PREFIX}*.json)
```

Only files like `2026-02-*.json` are used. This keeps the report focused and avoids mixing in old backfilled data from other months.

**Edge case:** If there are no files for the current month (e.g. new month and no writes yet), the script exits with “No historical data found.” Consider clarifying in the message that it’s “No data for [Month YYYY]” so it’s obvious it’s month-scoped.

### Mixed History Format Support

`tokens-command.sh` aggregates with a single `jq` expression that supports:

1. **API-style** – `.results[]` with fields like `uncached`, `cache_5m`, `cache_1h`, `cache_read`, `output` (and alternate names like `uncached_input_tokens`, `cache_read_input_tokens`, etc.).
2. **Legacy** – `.inputTokens` / `.outputTokens` (and optional `.model`), mapped into the same shape with cache fields as 0.

So both backfill-style and older daily-snapshot JSON files are handled in one place. Good for migration and mixed sources.

### Cache-Aware Cost in tokens-command.sh

Per-model cost uses cache multipliers consistent with CACHE_PRICING.md:

```bash
cost=$(echo "scale=2;
  ($uncached * $input_p) +
  ($cache_5m * $input_p * 1.25) +
  ($cache_1h * $input_p * 2.0) +
  ($cache_read * $input_p * 0.1) +
  ($output * $output_p)" | bc ...)
```

So the /tokens table now reflects cache when the history JSON contains cache breakdown (e.g. from backfill). Aligns with the documented pricing.

---

## 3. daily-token-counter.sh and pricing.json

### MiniMax in get_model_pricing()

- **Exact match** – If the model key exists in `pricing.json` (e.g. `minimax-M2.5`), that entry is used.
- **Case-insensitive MiniMax fallback** – If not found, any `models` key starting with `minimax` (case-insensitive) is used.
- **Final fallback** – If still no match, hardcoded MiniMax rates `0.0000001` / `0.0000005` are used and the function returns 0 (no error).

So unknown Claude models still exit with error; unknown models that “look like” MiniMax get MiniMax pricing. Consistent with supporting a second provider.

### pricing.json Additions

- **minimax-M2.5** – `$0.10/M in, $0.50/M out` (1e-7, 5e-7 per token).
- **minimax-M2.1** – Same rates, documented as previous model.

No cache_pricing structure change; cache multipliers in `tokens-command.sh` are hardcoded (1.25, 2.0, 0.1), which matches the existing `cache_pricing` section in `pricing.json`.

---

## 4. Security and Configuration

- **.gitignore** – `.env` and `.env.local` are ignored; API keys are not committed.
- **.env.example** – Only documents `MINIMAX_API_KEY`; no secrets.
- **tokens-command.sh** – `source "$SCRIPT_DIR/.env"` only if file exists; key is used only when `MINIMAX_API_KEY` is set.

**Suggestion:** In README or a dedicated setup doc, mention that for MiniMax plan display you can copy `.env.example` to `.env` and set `MINIMAX_API_KEY`, and that `.env` is gitignored.

---

## 5. Potential Issues and Improvements

### 5.1 bc / jq Dependency

`tokens-command.sh` uses `bc` and `jq` but doesn’t check for them (unlike `daily-token-counter.sh`). If either is missing, errors can be cryptic. **Recommendation:** Add at the top of `tokens-command.sh`:

```bash
for cmd in jq bc; do
  command -v "$cmd" &>/dev/null || { echo "❌ $cmd required"; exit 1; }
done
```

(And optionally `curl` if you want to fail fast when MiniMax is configured but curl is missing.)

### 5.2 Empty or Invalid MiniMax API Response

If the API returns non-JSON or a structure where `base_resp.status_code != 0`, the script still computes `PLAN_REMAINS=$((100 - PLAN_PCT))` with `PLAN_PCT=0`, so you get “0% used (100% remaining)”. That’s safe. If the API returns something like `current_interval_total_count: 0`, the `bc` expression could divide by zero. **Recommendation:** After reading `API_TOTAL` and `API_REMAINS`, if `API_TOTAL` is 0 or null, skip percentage calculation and show a short message (e.g. “Plan data unavailable”) instead of running `bc`.

### 5.3 GroupId and Endpoint

The MiniMax endpoint and GroupId are hardcoded. For flexibility and multi-tenant use, consider:

- `MINIMAX_GROUP_ID` (defaulting to current value)
- Optional `MINIMAX_CODING_PLAN_URL` if the endpoint path ever changes.

### 5.4 CHANGELOG and README

CHANGELOG.md currently stops at v1.2.0 (2026-02-09). The Feb 20 and related commits (MiniMax, /tokens current-month, mixed format, percentage fix) are not recorded. **Recommendation:** Add a v1.3.0 (or similar) section describing:

- MiniMax coding plan integration (balance, time window, reset countdown)
- /tokens limited to current month
- Mixed token history format support (legacy + API results)
- Cache-aware cost in /tokens
- MiniMax models and fallback in pricing
- Security: .env for MiniMax API key, .gitignore

README could briefly mention that `/tokens` can show MiniMax coding plan when `MINIMAX_API_KEY` is set, and point to `.env.example`.

---

## 6. What’s Working Well

- **Single aggregation path** – One jq pipeline for both legacy and API-style history keeps logic simple.
- **Cache-aware costs** – /tokens uses the same multipliers as in CACHE_PRICING.md when data is available.
- **Graceful degradation** – No MiniMax key → no plan block; no current-month files → clear “No historical data” message.
- **Pricing fallback** – MiniMax models get reasonable defaults even when the exact model id isn’t in `pricing.json`.
- **Security** – API key only in env; .env not committed; .env.example is safe to commit.
- **Portability** – GNU/BSD date handling for MiniMax time window is considered.

---

## 7. Summary Table

| Area              | Status | Notes |
|-------------------|--------|--------|
| MiniMax API       | OK     | Optional env key; consider GroupId in .env and zero-total guard |
| /tokens scope     | OK     | Current month only; clear and consistent |
| Mixed history     | OK     | Legacy + API formats supported in one pipeline |
| Cache pricing     | OK     | Multipliers applied in tokens-command when data present |
| daily-token-counter | OK   | MiniMax fallback in get_model_pricing; pricing.json extended |
| Security          | OK     | .env/.gitignore and .env.example in good shape |
| Docs              | TODO   | CHANGELOG and README could describe MiniMax and /tokens behavior |

---

## 8. Recommended Next Steps

1. **Add dependency checks** in `tokens-command.sh` for `jq` and `bc` (and optionally `curl` when MiniMax is used).
2. **Guard against zero total** in MiniMax percentage (skip division when `API_TOTAL` is 0 or null).
3. **Update CHANGELOG.md** with a v1.3.0 (or next) entry for MiniMax, /tokens current-month, mixed format, and pricing.
4. **Update README.md** with a short note on MiniMax coding plan and `.env.example`.
5. **(Optional)** Move MiniMax `GroupId` (and optionally API URL) to env for flexibility.

---

**Conclusion:** The latest changes integrate MiniMax and a cleaner, current-month-only /tokens display with cache-aware costs and mixed history support. The design is consistent and deployable; the items above are small robustness and documentation improvements.

---

## 9. Addendum (Feb 20, 2026 - Post-Review Fixes Applied)

The following review recommendations have now been implemented in commit `16d3333`:

1. **Fixed weekly/monthly aggregation double-counting in `daily-token-counter.sh`**
   - Weekly/monthly history now sums through **yesterday**, then adds today's cumulative values once.
2. **Fixed lock timeout behavior in `daily-token-counter.sh`**
   - Lock loop now sleeps 1 second per elapsed increment, matching the advertised 10-second timeout.
3. **Fixed `TOTAL_SAVED` counter in `backfill-token-history.sh`**
   - Replaced piped `while` subshell with process substitution so counter increments persist.
4. **Added dependency checks in `tokens-command.sh`**
   - Script now validates `curl`, `jq`, `bc`, and `base64` at startup.
5. **Added divide-by-zero guard in MiniMax plan percentage calculation**
   - Percentage now computes only when `API_TOTAL > 0`; otherwise defaults safely.
6. **Added regression checks and docs**
   - New `test-regressions.sh` verifies these critical fixes.
   - `README.md` now documents running regression checks.

### Updated Status on Prior Recommendations

- Section 5.1 (`bc`/`jq` dependency checks): **Done**
- Section 5.2 (zero-total guard): **Done**
- Other recommendations (GroupId env config, CHANGELOG expansion): **Still optional / pending**
