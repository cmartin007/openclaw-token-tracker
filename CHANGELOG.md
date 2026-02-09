# Changelog

## [1.2.0] - 2026-02-09

### Added
- **CACHE_PRICING.md** - Comprehensive prompt caching pricing guide
  - Cache cost multipliers (0.1x read, 1.25x/2.0x write)
  - Real-world cost examples with 50-90% savings
  - Break-even analysis for 5-minute vs 1-hour cache
  - Cost optimization strategies
  - Cache monitoring instructions
- **Cache pricing metadata** in pricing.json
  - Multipliers for reads, 5m writes, 1h writes
  - Documentation-only (not used in calculations)

### Changed
- pricing.json v1.1.0 → v1.2.0
  - Added `cache_pricing` section with multipliers
  - Clarified that base pricing doesn't include cache costs

### Documentation
- Added cache pricing to project documentation suite
- Referenced from PRICING_REVIEW.md

---

## [1.1.0] - 2026-02-09

### Changed
- **Externalized pricing configuration** to `pricing.json`
  - No more hardcoded pricing in the script
  - Easy updates without code changes
  - Just edit `pricing.json` to update prices or add new models
- Added pricing file validation on script startup
- Added detailed error messages for missing/invalid pricing
- **Added cost estimate disclaimers** to script output
  - Warns users that costs are estimates (base pricing only)
  - Notes that real costs may vary due to caching, long context, etc.
  - Recommends backfill script for actual costs

### Added
- `pricing.json` (v1.1.0) - External pricing configuration with **12 models**
  - Haiku 4.5, 3.5, 3
  - Sonnet 4.5, 4, 3.7 (deprecated)
  - Opus 4.6, 4.5, 4.1, 4, 3 (deprecated)
- `PRICING.md` - Complete guide for updating pricing
  - Cost variance examples
  - Limitations of base pricing
  - Instructions for getting actual costs
- `PRICING_EXTERNALIZATION.md` - Detailed implementation documentation
- `PRICING_REVIEW.md` - Comprehensive review of official Anthropic pricing
  - Analysis of prompt caching (90% discount potential)
  - Long context premiums (2x cost for >200K tokens)
  - Batch API discounts (50% off)
  - Tool use overhead costs
  - Real-world cost variance examples
- `test-pricing.sh` - Test script to validate pricing configuration
- Support for `PRICING_FILE` environment variable override

### Fixed
- Issue #7 from code review: Pricing data is hardcoded
- Added all missing Claude models to pricing configuration
- Updated pricing source URL to official docs page

### Documentation
- Updated README with cost estimate limitations
- Added warnings about cost variance (estimates vs actuals)
- Clarified dual-system approach (estimates + actuals)
- Referenced backfill script for accurate billing data

### Migration
- Existing installations: Just add `pricing.json` to your script directory
- The script will auto-detect and use it
- No other changes needed - fully backward compatible

---

## [1.0.0] - 2026-02-06

### Added
- Initial release
- `daily-token-counter.sh` - Main token usage tracker
- `token-history-logger.sh` - Daily snapshot logger
- Dynamic model detection (Haiku, Sonnet, Opus)
- Accurate Anthropic pricing per model
- Daily/Weekly/Monthly usage breakdown
- Persistent historical data storage
- Telegram bot integration (`/tokens` command)
- Color-coded terminal output
- Zero-token architecture (pure bash + cron)

### Features
- Real-time session token tracking
- Historical data aggregation (7+ days of data)
- Automatic daily snapshots via cron
- Input/Output token separation
- Cost calculation based on model pricing
- JSON history snapshots for archival
- 100% LLM-free operation

---

## Roadmap

### Future Enhancements
- [x] ~~External pricing configuration~~ (✅ v1.1.0)
- [ ] Alert when daily cost exceeds threshold
- [ ] Export to CSV for spreadsheets
- [ ] GraphQL endpoint for integrations
- [ ] Web dashboard for trends
- [ ] Multi-account tracking
- [ ] Budget forecasting
- [ ] Automated test suite
- [ ] Auto-fetch pricing from Anthropic API
