---
description: Daily usage cards in the popover show today's estimated cost, tokens and working time against yesterday, read from local Claude Code (and Mistral Vibe) session logs. Use when the cards are missing or the numbers look off.
---

# Daily Usage

Below a provider's quota cards, the popover can show what you've used **today**, compared with **yesterday**:

| Card | Shows | Sub-line |
|---|---|---|
| **Cost Usage** | Estimated spend at API list prices, in USD | "Saved $X (N%)" that prompt caching saved |
| **Token Usage** | Input + output + cache tokens | "N% from cache" |
| **Working Time** | Time you were active, shown only when there is some | — |

Each card ends with a line like "Vs Sep 23 +$5.00 (12.5%)": green when today is lower, orange when it's higher.

## Quick start

The cards are **on by default**. Turn them off or on in Settings → **General** → **Daily Usage Cards**.

They appear for providers that keep local session logs:

| Provider | Reads |
|---|---|
| Claude | Claude Code transcripts in `~/.claude/projects/**/*.jsonl` |
| Mistral | Vibe session metadata in `~/.vibe/logs/session/` |
| Extensions | Whatever the extension's `dailyUsage` section returns; see [extensions](../extensions/README.md) |

Nothing is sent anywhere; ClaudeBar only reads the files.

## How the numbers are worked out

- **Today and yesterday** are calendar days in your time zone. For Claude, only files changed since the start of yesterday are read.
- **Mistral** cost and tokens are the totals Vibe itself records for each session. The rest of this section is about Claude.
- **Cost** is an estimate: each message's tokens times the model's list price per million tokens (input, output, cache write, cache read). Unknown Anthropic models are priced by family (Opus, Haiku), and anything else at Sonnet rates. It won't match your subscription bill, which is flat; it shows what the same work would cost on the API.
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
- **New models**: until a model is added to ClaudeBar's price table, it's priced by the fallback rules above — unless its name is one of the open-weight families, or it was served locally. Either way, free.

## See also

[design.md](design.md) — how duplicates are found and why totals used to be ~4× too high · [extensions](../extensions/README.md) · [Claude](../../providers/claude/README.md)
