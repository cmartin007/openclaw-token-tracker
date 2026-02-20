# Commands

## `/tokens` — Show Token Usage

Display current month token usage with detailed cost breakdown by model.

### Format

```
/tokens
```

### Response

```
💳 MiniMax Coding Plan: 15% used (85% remaining) • 05:00-10:00 (UTC) • Resets in 3 hr 7 min

📊 February 2026 - $80.10 total

| Model        | Uncached | Cache 5m  | Cache Read | Output  | Cost   |
| ------------ | -------- | --------- | ---------- | ------- | ------ |
| MiniMax      | 326.4K   | 0         | 0          | 5.6K    | included |
| Haiku 4.5    | 6.1K     | 11.4M     | 36.9M      | 156.1K  | $18.75  |
| Opus 4.5     | 392      | 383.1K    | 1.2M       | 11.1K   | $3.30   |
| Sonnet 4     | 8.8K     | 8.8M      | 70.0M      | 255.3K  | $58.03  |
| Sonnet 4.5   | 790      | 0         | 0          | 1.3K    | $0.02   |
| ------------ | -------- | --------- | ---------- | ------- | ------ |
| TOTAL        |          |           |            | 129.6M  | $80.10  |

You're almost out of MiniMax prompts - only 85 left! 🐕
```

### Features

- **Current month only** - Shows only this month's usage (not all-time)
- **MiniMax coding plan** - Displays plan balance if `MINIMAX_API_KEY` is configured
- **Detailed breakdown** - Uncached, Cache 5m, Cache Read, Output columns
- **Model versions** - Shows Haiku 4.5, Opus 4.5, Sonnet 4, Sonnet 4.5
- **Cache-aware pricing** - Applies cache multipliers (1.25x for 5m, 0.1x for reads)
- **Cost** - MiniMax shows "included" (coding plan), others show actual cost

### Handler

```
/home/openclaw/.openclaw/workspace/git-repos/openclaw-token-tracker/tokens-command.sh
```

### Cost

~$0 (pure bash, no LLM calls)

### Setup

1. Ensure `tokens-command.sh` is in your workspace:
   ```bash
   cp tokens-command.sh /home/openclaw/.openclaw/workspace/
   chmod +x /home/openclaw/.openclaw/workspace/tokens-command.sh
   ```

2. (Optional) For MiniMax coding plan display:
   ```bash
   cp .env.example .env
   # Edit .env and add your MINIMAX_API_KEY
   ```

3. Register `/tokens` command with BotFather in Telegram

### Testing

Run the regression test suite after any changes:
```bash
./test-regressions.sh
```
