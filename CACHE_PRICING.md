# Prompt Caching Pricing Guide

**Source:** https://platform.claude.com/docs/en/about-claude/pricing  
**Last Updated:** February 9, 2026

---

## Overview

**Prompt caching** is Anthropic's feature that allows you to reuse previously processed context, dramatically reducing costs for repeated prompts.

**Key Benefit:** Cache reads cost **90% less** than regular input tokens.

---

## How Cache Pricing Works

### Cache Cost Multipliers

All cache pricing is based on **multipliers** applied to base input token costs:

| Cache Operation | Multiplier | Cost vs Base |
|----------------|-----------|-------------|
| **Cache read (hit)** | 0.1x | 90% cheaper |
| **5-minute cache write** | 1.25x | 25% more expensive |
| **1-hour cache write** | 2.0x | 100% more expensive |
| **Regular input (no cache)** | 1.0x | Standard price |

**Output tokens are NOT cached** - they always cost the standard rate.

---

## Cache Pricing by Model

### Haiku 4.5

| Operation | Cost per 1M tokens | Notes |
|-----------|-------------------|-------|
| Base input | $1.00 | Standard |
| 5m cache write | $1.25 | 25% premium |
| 1h cache write | $2.00 | 2x premium |
| Cache read | **$0.10** | 90% savings! |
| Output | $5.00 | Not cached |

### Sonnet 4.5

| Operation | Cost per 1M tokens | Notes |
|-----------|-------------------|-------|
| Base input | $3.00 | Standard |
| 5m cache write | $3.75 | 25% premium |
| 1h cache write | $6.00 | 2x premium |
| Cache read | **$0.30** | 90% savings! |
| Output | $15.00 | Not cached |

### Opus 4.6

| Operation | Cost per 1M tokens | Notes |
|-----------|-------------------|-------|
| Base input | $5.00 | Standard |
| 5m cache write | $6.25 | 25% premium |
| 1h cache write | $10.00 | 2x premium |
| Cache read | **$0.50** | 90% savings! |
| Output | $25.00 | Not cached |

---

## Real-World Cost Examples

### Example 1: Simple Chat with Context

**Scenario:** Customer support bot with 50K token knowledge base

**Without caching:**
```
Request 1: 50K context + 1K query = 51K input
Request 2: 50K context + 1K query = 51K input
Request 3: 50K context + 1K query = 51K input
...
Total: 153K input tokens × $3/M (Sonnet) = $0.459
```

**With 5-minute caching:**
```
Request 1: 50K cache write + 1K input = $0.1875 + $0.003 = $0.1905
Request 2: 50K cache read + 1K input  = $0.015 + $0.003 = $0.018
Request 3: 50K cache read + 1K input  = $0.015 + $0.003 = $0.018
...
Total: $0.2265 (51% savings!)
```

### Example 2: Long-Running Conversation

**Scenario:** 10-turn conversation, context grows each turn

**Without caching (Opus 4.6):**
```
Turn 1:  10K input × $5/M = $0.05
Turn 2:  20K input × $5/M = $0.10
Turn 3:  30K input × $5/M = $0.15
...
Turn 10: 100K input × $5/M = $0.50
Total: $2.75
```

**With 5-minute caching:**
```
Turn 1:  10K cache write = $0.0625
Turn 2:  10K cache read + 10K write = $0.005 + $0.0625 = $0.0675
Turn 3:  20K cache read + 10K write = $0.010 + $0.0625 = $0.0725
...
Turn 10: 90K cache read + 10K write = $0.045 + $0.0625 = $0.1075
Total: $0.7125 (74% savings!)
```

### Example 3: RAG System with Large Document Set

**Scenario:** 500K token document corpus, 1,000 queries per day

**Without caching (Sonnet 4.5):**
```
1,000 queries × 500K context = 500M tokens
500M × $3/M = $1,500/day
```

**With 1-hour caching:**
```
Cache write (once per hour × 24): 24 × 500K × $6/M = $72
Cache reads: 976 queries × 500K × $0.30/M = $146.40
Query tokens: 1,000 × 1K × $3/M = $3
Total: $221.40/day (85% savings!)
```

### Example 4: Code Analysis Agent

**Scenario:** Analyzing 100K line codebase, 50 queries

**Without caching (Opus 4.6):**
```
50 queries × 200K context (code) = 10M tokens
10M × $5/M = $50
```

**With 5-minute caching:**
```
Cache write (first query): 200K × $6.25/M = $1.25
Cache reads (49 queries):  9.8M × $0.50/M = $4.90
Total: $6.15 (88% savings!)
```

---

## Cache Duration Strategies

### 5-Minute Cache (Default)

**Best for:**
- Real-time chat applications
- Interactive sessions
- Rapid consecutive requests

**Characteristics:**
- Lower write cost (1.25x)
- Good for burst traffic
- Expires quickly

**Cost:** Write premium of 25%

### 1-Hour Cache

**Best for:**
- Background processing
- Scheduled batch jobs
- Long-running agents
- RAG systems with stable knowledge bases

**Characteristics:**
- Higher write cost (2.0x)
- Amortizes better over many requests
- Longer persistence

**Cost:** Write premium of 100%

### When Each Makes Sense

| Use Case | Recommended | Why |
|----------|------------|-----|
| Customer support chat | 5-minute | Burst conversations, shorter sessions |
| Document Q&A system | 1-hour | Same docs queried repeatedly |
| Code review agent | 5-minute | Interactive, session-based |
| Research assistant | 1-hour | Large corpus, many queries |
| API rate limiting workaround | 5-minute | Quick bursts within limits |

---

## Break-Even Analysis

### When Does Caching Pay Off?

**5-minute cache:**
```
Write cost: 1.25x base
Read cost:  0.1x base

Break-even: After 2 reads
(1.25 + 0.1 + 0.1 = 1.45 < 1.0 + 1.0 + 1.0)
```

**1-hour cache:**
```
Write cost: 2.0x base
Read cost:  0.1x base

Break-even: After 11 reads
(2.0 + 10×0.1 = 3.0 < 11×1.0)
```

### Rule of Thumb

- **Use 5-minute cache** if you'll reuse context 2+ times within 5 minutes
- **Use 1-hour cache** if you'll reuse context 11+ times within 1 hour
- **Don't cache** if context is only used once

---

## Cost Optimization Strategies

### 1. Cache Stable Context Only

**Good:**
```
[CACHED: System prompt + Knowledge base + Examples]
[NOT CACHED: User query (changes each time)]
```

**Bad:**
```
[CACHED: Everything including unique user query]
```

### 2. Update Cache Strategically

If your knowledge base updates hourly:
- Use 1-hour cache
- Accept slightly stale data for 90% cost savings
- Refresh on schedule, not per-request

### 3. Session-Based Caching

Group related requests:
```
User A, Request 1: Write cache (system prompt)
User A, Request 2-10: Read cache (90% savings)
User B, Request 1: New cache (can't reuse User A's)
```

### 4. Shared vs Per-User Caching

**Shared context (better):**
- Company knowledge base
- Documentation
- Code repositories
- Public data

**Per-user context (limited value):**
- Personal preferences
- Private conversations
- User-specific data

---

## Our System's Cache Support

### What We Track: ❌ None

Our `daily-token-counter.sh` **cannot distinguish** between:
- Cache writes vs regular input
- Cache reads vs regular input
- 5-minute vs 1-hour cache TTL

**Why?** OpenClaw session data doesn't expose cache metrics.

### Getting Actual Cache Costs: ✅ Use Backfill Script

The `backfill-token-history.sh` script fetches real costs from Anthropic Admin API, which includes:

```json
{
  "usage_type": "input_no_cache",
  "cost_usd": 0.005
},
{
  "usage_type": "input_cache_read",
  "cost_usd": 0.0005
},
{
  "usage_type": "input_cache_write_5m",
  "cost_usd": 0.00625
}
```

**This is the ONLY way to track cache costs accurately.**

---

## Cache Pricing in pricing.json

We've added cache multipliers to `pricing.json` v1.2.0:

```json
{
  "cache_pricing": {
    "write_5m_multiplier": 1.25,
    "write_1h_multiplier": 2.0,
    "read_multiplier": 0.1,
    "note": "Cache reads provide 90% cost savings vs base input"
  }
}
```

**Purpose:** Documentation and reference, not active calculation.

---

## Estimating Cache Impact

### Conservative Estimate (Worst Case)

Assume **no caching benefit:**
- Use base pricing from `pricing.json`
- This is what our daily counter shows
- Safe underestimate of costs

### Optimistic Estimate (Best Case)

Calculate with high cache hit rate:

**Python example:**
```python
base_input = 0.000005  # Opus 4.6
cache_read = base_input * 0.1

# Assume 80% cache hit rate
total_tokens = 10_000_000
cache_hits = total_tokens * 0.8
cache_misses = total_tokens * 0.2

cost = (cache_hits * cache_read) + (cache_misses * base_input)
# $4.00 + $10.00 = $14.00 vs $50.00 without caching
```

### Realistic Estimate (Actual Usage)

**Use the backfill script!** It shows real cache performance.

---

## Common Cache Scenarios

### Scenario 1: Interactive AI Assistant

**Pattern:** 10-turn conversation, 20K context per turn

| Turn | Operation | Cost (Opus) |
|------|-----------|-------------|
| 1 | 20K write | $0.125 |
| 2-10 | 20K read × 9 | $0.090 |
| **Total** | | **$0.215** |

**Without cache:** $1.00 (78% savings)

### Scenario 2: Document Q&A (1,000 queries/day)

**Pattern:** 200K document, queried throughout the day

| Time | Operation | Cost (Sonnet) |
|------|-----------|---------------|
| 00:00 | 200K write (1h) | $1.20 |
| 00:01-00:59 | ~60 × 200K read | $3.60 |
| 01:00 | 200K write (1h) | $1.20 |
| ... | ... | ... |
| **Daily** | **24 writes + 976 reads** | **$87.36** |

**Without cache:** $600 (85% savings)

### Scenario 3: Code Review Agent

**Pattern:** 50K codebase, reviewed in 5-minute session with 20 queries

| Query | Operation | Cost (Haiku) |
|-------|-----------|--------------|
| 1 | 50K write (5m) | $0.0625 |
| 2-20 | 50K read × 19 | $0.095 |
| **Total** | | **$0.1575** |

**Without cache:** $1.00 (84% savings)

---

## Monitoring Cache Performance

### Using Anthropic Console

1. Go to https://console.anthropic.com/settings/billing
2. View usage breakdown by type:
   - `input_no_cache`
   - `input_cache_write_5m`
   - `input_cache_write_1h`
   - `input_cache_read`

### Using Our Backfill Script

```bash
./backfill-token-history.sh
cat token-history/2026-02-09.json | jq '.costs'
```

Output shows cache breakdown:
```json
[
  {"usage_type": "input_no_cache", "cost_usd": 15.00},
  {"usage_type": "input_cache_read", "cost_usd": 0.50},
  {"usage_type": "output", "cost_usd": 25.00}
]
```

---

## FAQs

### Q: Does every model support caching?

**A:** Yes! All Claude models support prompt caching with the same multipliers (0.1x read, 1.25x/2.0x write).

### Q: Can I cache output tokens?

**A:** No. Only input tokens can be cached. Output tokens always cost standard rates.

### Q: How do I enable caching?

**A:** Use the `cache_control` parameter in your API requests. See [Anthropic docs](https://docs.anthropic.com/claude/docs/prompt-caching) for details.

### Q: What happens when cache expires?

**A:** Next request pays write cost again to rebuild cache.

### Q: Can I see cache hit rate?

**A:** Not directly in the API response, but you can calculate it from usage data in the Anthropic Console or backfill script.

### Q: Do cache costs stack with other pricing?

**A:** Yes! Cache multipliers apply to:
- Base pricing
- Long context pricing (>200K)
- Data residency pricing (1.1x)
- NOT batch API (no caching support)

---

## Summary

### Key Takeaways

1. **Cache reads save 90%** - Massive cost reduction for repeated context
2. **Write premium is small** - 25% or 100% upfront, pays off quickly
3. **Break-even is fast** - 2 reads (5m) or 11 reads (1h)
4. **Our counter doesn't track it** - Use backfill script for actuals
5. **Real savings are huge** - 50-90% reduction in typical workloads

### Recommendations

1. **Use caching** for any repeated context
2. **Monitor actual usage** via backfill script
3. **Optimize cache strategy** based on access patterns
4. **Don't trust base estimates** if you use caching heavily

---

**For more information:**
- [Anthropic Prompt Caching Docs](https://docs.anthropic.com/claude/docs/prompt-caching)
- [Official Pricing Page](https://platform.claude.com/docs/en/about-claude/pricing)
- Our `PRICING_REVIEW.md` - Cost variance analysis

**Last updated:** February 9, 2026
