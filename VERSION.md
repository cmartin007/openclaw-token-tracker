# Version Notes

## Current Version: 1.3.0

**Released:** 2026-02-20

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| [1.3.0](#130---2026-02-20) | 2026-02-20 | MiniMax integration, detailed token breakdown, model versions |
| [1.2.0](#120---2026-02-09) | 2026-02-09 | Cache pricing, externalized pricing |
| [1.0.0](#100---2026-02-06) | 2026-02-06 | Initial release |

---

## 1.3.0 - 2026-02-20

### What's New

- **MiniMax Coding Plan** - Shows balance, usage %, time window, reset countdown
- **Detailed Token Breakdown** - Columns: Uncached, Cache 5m, Cache Read, Output
- **Model Versions** - Haiku 4.5, Opus 4.5, Sonnet 4, Sonnet 4.5
- **Current Month Only** - No all-time data clutter

### Files Changed

- `tokens-command.sh` - Complete rewrite for new display
- `daily-token-counter.sh` - Bug fixes for aggregation
- `backfill-token-history.sh` - Counter fix
- `pricing.json` - Added MiniMax models
- `CHANGELOG.md` - Updated
- `README.md` - Added MiniMax section
- `COMMANDS.md` - Updated /tokens documentation

### Breaking Changes

- `/tokens` output format changed (now shows detailed breakdown table)
- Only shows current month (not all-time)

---

## 1.2.0 - 2026-02-09

### What's New

- **Cache Pricing** - Documented cache multipliers
- **Externalized Pricing** - `pricing.json` for easy updates

### Files Added

- `CACHE_PRICING.md`
- `pricing.json`
- `PRICING.md`
- `PRICING_EXTERNALIZATION.md`

---

## 1.0.0 - 2026-02-06

### Initial Release

- `daily-token-counter.sh` - Main tracker
- `token-history-logger.sh` - Daily snapshots
- Basic Haiku/Sonnet/Opus detection
- Daily/weekly/monthly breakdowns

---

## Development Notes

### Running Tests

```bash
# Regression tests
./test-regressions.sh

# Pricing validation
./test-pricing.sh
```

### Common Tasks

| Task | Command |
|------|---------|
| Run /tokens | `/home/openclaw/.openclaw/workspace/git-repos/openclaw-token-tracker/tokens-command.sh` |
| Daily snapshot | `/home/openclaw/.openclaw/workspace/token-history-logger.sh` |
| Backfill data | `/home/openclaw/.openclaw/workspace/git-repos/openclaw-token-tracker/backfill-token-history.sh` |
| Add cron | `crontab -e` |

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `MINIMAX_API_KEY` | MiniMax platform API key | No (for coding plan display) |
| `ANTHROPIC_ADMIN_API_KEY` | For backfill script | No |

---

*This is a live document. Update as changes are made.*
