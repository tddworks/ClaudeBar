---
description: Daily usage cards in the popover show today's estimated cost, tokens and working time against yesterday, read from local Claude Code (and Mistral Vibe or Oh My Pi) session logs. Use when the cards are missing or the numbers look off.
---

# Daily Usage

Below a provider's quota cards, the popover can show what you've used **today**, compared with **yesterday**:

| Card | Shows | Sub-line |
|---|---|---|
| **Cost Usage** | Estimated spend at API list prices, in USD | "Saved $X (N%)" that prompt caching saved |
| **Token Usage** | Input + output + cache tokens | "N% from cache" |
| **Working Time** | Time you were active, shown only when there is some | — |

Each card ends with a line like "Vs Sep 23 +$5.00 (12.5%)": green when today is lower, orange when it's higher.

Below them, **Daily usage — last 30 days** charts the same login's last thirty days, one bar a day: **Cost**, **Tokens** (input and output) or **Cache** (writes and reads), with the thirty-day total in the corner. Hover a bar to see that day.

## Quick start

The cards are **on by default**. Turn them off or on in Settings → **General** → **Daily Usage Cards**.

They appear for providers that keep local session logs:

| Provider | Reads |
|---|---|
| Claude | Claude Code transcripts in `~/.claude/projects/**/*.jsonl`; an added account, its own folder's `projects/`. Your usual login also gets a **Claude Desktop · Token Usage** card from `~/Library/Application Support/Claude/buddy-tokens.json`, with tokens only and no cost |
| Mistral | Vibe session metadata in `~/.vibe/logs/session/` |
| Oh My Pi | omp's session logs in `~/.omp/agent/sessions/**/*.jsonl` (or `$PI_CODING_AGENT_DIR/sessions`), subagents included; every account omp drives adds up under Oh My Pi. See [Oh My Pi](../../providers/omp/README.md#daily-usage) |
| Extensions | Whatever the extension's `dailyUsage` section returns; see [extensions](../extensions/README.md) |

The cards and the chart only read these files; nothing is sent anywhere. If you join the [Leaderboard](../leaderboard/README.md), the providers you tick there upload their daily token totals, and nothing else from these logs.

## How the numbers are worked out

- **Days** are calendar days in your time zone. A day is summed once, an hour after it ends, and kept in `~/.claudebar/usage-history/`; after that only today's logs are read. Delete that folder to have every day summed again.
- **Oh My Pi** cost is what omp recorded for each model call; its tokens are omp's own counts per call.
- **Mistral** cost and tokens are the totals Vibe itself records for each session. The rest of this section is about Claude.
- **Cost** is an estimate: each message's tokens times the model's list price per million tokens (input, output, cache write, cache read). A cache write Claude Code keeps for an hour costs the higher 1-hour price; Claude Code writes most of its cache that way. Unknown Anthropic models are priced by family (Opus, Haiku), and anything else at Sonnet rates. It won't match your subscription bill, which is flat; it shows what the same work would cost on the API.
- **Local models cost nothing.** A model ClaudeBar recognises as an open-weight one (Qwen, Llama, Gemma, Mistral, …), or any model at all when Claude Code is pointed at a loopback `ANTHROPIC_BASE_URL` (ollama, LM Studio, llama.cpp), is billed at $0. Its tokens are still counted. A hosted open-weight endpoint counts too — a `qwen3-max` or `*/llama-*` model served from someone else's cloud also shows $0, so don't read a zero here as proof nobody charged you upstream.
- **Duplicates are removed.** Claude Code writes the same usage several times while streaming, in parallel tool calls, and in resumed or branched sessions. ClaudeBar keeps one entry per message and request, so the totals line up with `claude /cost`. [design.md](design.md) has the details.
- **Working time** adds up the stretches between your first and last message, and starts a new stretch after a gap of more than 30 minutes.

## Gotchas

- **Claude's cards update when you open the popover**, not in the background, because scanning the logs costs more than a quota check. The menu bar never shows them.
- **No cards at all**: there were no sessions today or yesterday, the toggle is off, or the provider doesn't keep local logs (Codex, Gemini, Copilot and the others).
- **Cost looks high on a subscription**: that's expected. It's the API list-price value of your usage, not what you paid.
- **Cost is $0 while you're on a local model**: also expected. Nothing bills you per token for inference on your own machine, so ClaudeBar reports $0 rather than inventing a Sonnet-rate figure. Token Usage keeps counting.
- **Cost is $0 but an invoice still arrived**: ClaudeBar only sees the model name and the endpoint's host, so a hosted open-weight model and a local proxy in front of a paid API both read as free. When the two disagree, the invoice wins.
- **Usage on another machine** isn't counted. Only this Mac's logs are read.
- **New models**: until a model is added to ClaudeBar's price list (`claude-prices.json`), it's priced by the fallback rules above — unless its name is one of the open-weight families, or it was served locally. Either way, free.
- **The chart's first appearance takes a moment**: the first time, thirty days of logs are read; after that the closed days are kept and only today is read.

## See also

[design.md](design.md) — how a login's logs become days · [dedup.md](dedup.md) — how duplicates are found and why totals used to be ~4× too high · [extensions](../extensions/README.md) · [Claude](../../providers/claude/README.md)
