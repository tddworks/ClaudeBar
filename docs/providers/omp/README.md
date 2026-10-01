---
description: Track the rate-limit windows of every account Oh My Pi (omp) is signed into, such as Claude, Codex and Z.ai, via `omp usage --json`. Use when setting up Oh My Pi or when an account shows "No usage reported".
---

# Oh My Pi

Oh My Pi is a coding-agent harness that holds sign-ins for several upstream providers. ClaudeBar shows every rate-limit window `omp` reports, grouped into one section per upstream account (for example "Claude", "Codex · work"), each with its reset time. USD limits appear as spend meters.

## Setup

1. Install Oh My Pi so `omp` is on your PATH (Bun installs in `~/.bun/bin` are found too), and sign in to the upstream providers inside `omp`.
2. Check that `omp usage --json` prints your accounts in a terminal.
3. Settings → Providers → Oh My Pi → make sure the switch is on (it is on by default).

There are no Oh My Pi-specific settings. ClaudeBar reads only what `omp usage` reports; it never touches the upstream credentials.

## Gotchas

- **"No usage reported"** under an account means `omp` holds a sign-in for it but produced no usable quota: an expired session, a failed fetch, or a provider with no quota API (Ollama, for example). Fix it inside `omp`, then refresh.
- **Background refresh is at most every 5 minutes.** `omp usage` caches upstream reports and each run starts a Bun process, so faster polling would only repeat the same data. Clicking refresh is not limited. If Oh My Pi is one of the providers refreshed in the background, the whole background cycle slows to 5 minutes.
- **Several accounts on one upstream provider** get a short account tag in their labels ("Claude 7d · jkjk987…"). The menu bar shortens long tags; the full tag keeps saved menu-bar selections stable.
- A USD limit with no cap shows as a note ("$X spent · no cap"), not as a percentage.
- Error messages never include `omp`'s raw output, because it contains account emails and ids. Run `omp usage --json` yourself to see what failed.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · the dedicated Claude, Codex or Z.ai providers if you'd rather track one account directly
