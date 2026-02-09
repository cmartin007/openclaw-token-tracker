# Pricing Configuration

## Overview

Model pricing is now externalized to `pricing.json` for easy updates without code changes.

## Pricing File Location

**Default:** `pricing.json` (same directory as the script)

**Override:** Set the `PRICING_FILE` environment variable:
```bash
export PRICING_FILE=/path/to/custom/pricing.json
./daily-token-counter.sh
```

## Pricing File Format

```json
{
  "version": "1.0.0",
  "updated": "2026-02-06",
  "source": "https://www.anthropic.com/pricing",
  "models": {
    "model-identifier": {
      "input_cost_per_token": 0.000001,
      "output_cost_per_token": 0.000005,
      "display_name": "Model Display Name ($X.XX/M in, $X.XX/M out)",
      "notes": "Optional notes about the pricing"
    }
  }
}
```

## Updating Pricing

### When to Update

Update pricing when:
- Anthropic announces price changes
- New models are released
- You want to add custom models

### How to Update

1. **Verify current pricing** at https://www.anthropic.com/pricing

2. **Edit pricing.json**:
   ```bash
   nano pricing.json
   ```

3. **Update the relevant fields**:
   - `input_cost_per_token` - Cost per input token (e.g., $1/M = 0.000001)
   - `output_cost_per_token` - Cost per output token (e.g., $5/M = 0.000005)
   - `display_name` - Human-readable name shown in reports
   - `updated` - Date you verified the pricing

4. **Validate the JSON**:
   ```bash
   jq '.' pricing.json
   ```

5. **Test the script**:
   ```bash
   ./daily-token-counter.sh
   ```

### Adding New Models

To add a new model:

```json
{
  "models": {
    "claude-new-model-1-0": {
      "input_cost_per_token": 0.000002,
      "output_cost_per_token": 0.000010,
      "display_name": "Claude New Model 1.0 ($2.00/M in, $10.00/M out)",
      "notes": "New model released 2026-XX-XX"
    }
  }
}
```

The script will automatically:
- Detect the model from OpenClaw sessions
- Load pricing from the config file
- Calculate costs correctly

## Current Pricing (as of Feb 6, 2026)

**Source:** https://platform.claude.com/docs/en/about-claude/pricing

### Base Pricing (Covered by pricing.json)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Claude Haiku 4.5 | $1.00 | $5.00 |
| Claude Sonnet 4.5 | $3.00 | $15.00 |
| Claude Opus 4.6 | $5.00 | $25.00 |

### ⚠️ Important Pricing Limitations

**This configuration covers base pricing only.** Real costs may vary significantly due to:

1. **Prompt Caching** (can reduce costs by 90%)
   - Cache writes: 1.25x-2x base input cost
   - Cache reads: 0.1x base input cost (90% savings!)

2. **Long Context Premium** (doubles costs for large inputs)
   - Inputs >200K tokens cost 2x more
   - Example: Opus 4.6 becomes $10/M input, $37.50/M output

3. **Batch API Discount** (50% off for async requests)
   - Half price for non-time-sensitive workloads

4. **Fast Mode** (6x cost for faster responses)
   - Opus 4.6 only: $30-60/M input, $150-225/M output

5. **Tool Use Overhead**
   - Web search: Additional $10 per 1,000 searches
   - Code execution: $0.05/hour (1,550 free hours/month)
   - System prompt: 346-735 tokens per request

6. **Data Residency** (1.1x for US-only routing)

### Getting Accurate Costs

For precise cost tracking including all modifiers:

1. **Use the backfill script** - Fetches actual costs from Anthropic Admin API
   ```bash
   ./backfill-token-history.sh
   ```

2. **Check your Anthropic Console** - https://console.anthropic.com/settings/billing

3. **Review official docs** - https://platform.claude.com/docs/en/about-claude/pricing

**Note:** The daily counter shows **estimated** costs using base pricing. The backfill script shows **actual** costs with all modifiers applied.

## Troubleshooting

### Error: Pricing configuration file not found

**Cause:** The script can't find `pricing.json`

**Solution:** 
```bash
# Check if file exists
ls -la pricing.json

# If missing, create it or clone from repo
curl -O https://raw.githubusercontent.com/.../pricing.json
```

### Error: Unknown model not found in pricing file

**Cause:** Your OpenClaw session uses a model not in the pricing file

**Solution:**
1. Check which model you're using:
   ```bash
   openclaw sessions list --json | jq '.sessions[0].model'
   ```

2. Add the model to `pricing.json` (see "Adding New Models" above)

### Error: Invalid pricing configuration file

**Cause:** The `pricing.json` file has invalid JSON syntax

**Solution:**
```bash
# Validate JSON
jq '.' pricing.json

# Common issues:
# - Missing comma between fields
# - Trailing comma after last field
# - Unquoted strings
# - Comments (JSON doesn't support comments)
```

## Benefits of External Configuration

### Before (Hardcoded)
- ❌ Price changes required code edits
- ❌ Risk of syntax errors in bash
- ❌ Hard to track pricing history
- ❌ Can't override for testing

### After (External Config)
- ✅ Price changes are data edits (no code changes)
- ✅ JSON validation catches errors early
- ✅ Git history tracks pricing changes
- ✅ Can override with environment variable
- ✅ Same config file can be shared across tools

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-09 | 1.0.0 | Initial external pricing configuration |
| 2026-02-06 | - | Pricing was hardcoded in script |

## Migration from Hardcoded Pricing

If you're upgrading from the hardcoded version:

1. **Create pricing.json** in the script directory
2. **Copy the template** from this document
3. **Verify pricing** at https://www.anthropic.com/pricing
4. **Test the script** to ensure it works
5. **No other changes needed** - the script is backward compatible

## Security Considerations

- **Pricing file is read-only** - Script only reads, never writes
- **No secrets** - Contains only public pricing information
- **World-readable** - File can be shared openly (no sensitive data)
- **Validation** - Script validates file format before use

## Future Enhancements

Potential future improvements:
- Auto-fetch pricing from Anthropic API
- Pricing history tracking
- Multi-region pricing support
- Volume discounts configuration
- Custom cost allocations per user/project

---

**Questions?** Check the main README or open an issue.
