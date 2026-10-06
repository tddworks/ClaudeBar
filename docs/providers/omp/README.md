---
description: Track the rate-limit windows of every account Oh My Pi (omp) is signed into via `omp usage --json`, plus its daily tokens and cost from omp's session logs. Use when setting up Oh My Pi or when an account shows "No usage reported".
---

# Oh My Pi

Oh My Pi is a coding-agent harness that holds sign-ins for several upstream providers. ClaudeBar shows every rate-limit window `omp` reports, grouped into one section per upstream account (for example "Claude", "Codex · work"), each with its reset time. USD limits appear as spend meters. Below them, the [daily usage](../../features/daily-usage/README.md) cards and chart show what omp used on this Mac, and Oh My Pi can be shared on the [leaderboard](../../features/leaderboard/README.md).

## Setup

1. Install Oh My Pi so `omp` is on your PATH (Bun installs in `~/.bun/bin` are found too), and sign in to the upstream providers inside `omp`.
2. Check that `omp usage --json` prints your accounts in a terminal.
3. Settings → Providers → Oh My Pi → make sure the switch is on (it is on by default).

There are no Oh My Pi-specific settings. ClaudeBar reads what `omp usage` reports and omp's session logs; it never touches the upstream credentials.

## Daily usage

- **Read from** omp's session logs in `~/.omp/agent/sessions` (or `$PI_CODING_AGENT_DIR/sessions`): your sessions, their subagents and advisor, and the model calls omp makes outside the chat, such as its memory's.
- **One total for every account.** Claude, Codex, Kimi and the rest all add up under Oh My Pi. omp keeps its own logs, apart from Claude Code's and Codex's, so nothing is counted twice with the Claude or Codex providers.
- **A forked session's copied turns count once**, as in omp's own stats.
- **Cost** is what omp recorded for each call, at the model's list price. A call omp recorded no price for adds $0, so a provider omp can't price shows tokens but little or no cost.

## Gotchas

- **"No usage reported"** under an account means `omp` holds a sign-in for it but produced no usable quota: an expired session, a failed fetch, or a provider with no quota API (Ollama, for example). Fix it inside `omp`, then refresh.
- **Oh My Pi refreshes at most every 5 minutes.** `omp usage` caches upstream reports and each run starts a Bun process, so faster polling would only repeat the same data. Within 5 minutes, clicking refresh shows the same report. If Oh My Pi is one of the providers refreshed in the background, the whole background cycle slows to 5 minutes.
- **Several accounts on one upstream provider** get a short account tag in their labels ("Claude 7d · jkjk987").
- A USD limit with no cap shows as a note ("$X spent · no cap"), not as a percentage.
- Error messages never include `omp`'s raw output, because it contains account emails and ids. Run `omp usage --json` yourself to see what failed.
- **No daily usage cards** with omp running: ClaudeBar reads `~/.omp/agent/sessions` unless `PI_CODING_AGENT_DIR` is in ClaudeBar's own environment. A variable exported only in `~/.zshrc` isn't seen when the app starts from Finder or at login. Named profiles, an XDG data folder and `--session-dir` aren't read.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · the dedicated Claude, Codex or Z.ai providers if you'd rather track one account directly
