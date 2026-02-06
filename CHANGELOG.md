# Changelog

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
- [ ] Alert when daily cost exceeds threshold
- [ ] Export to CSV for spreadsheets
- [ ] GraphQL endpoint for integrations
- [ ] Web dashboard for trends
- [ ] Multi-account tracking
- [ ] Budget forecasting
