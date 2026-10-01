---
description: Track Kiro monthly plan credits and bonus credits by running `kiro-cli` and reading its `/usage` output. Use when setting up Kiro or when it shows nothing or "No quota data found in Kiro CLI output".
---

# Kiro

Shows your Kiro plan credits for the month (with the date they reset) and any bonus credits (with the days until they expire).

## Setup

1. Install the Kiro CLI: `curl -fsSL https://cli.kiro.dev/install | bash`. **Don't** use `pip install kiro-cli` or `uv tool install kiro-cli`: the `kiro-cli` package on PyPI is an unrelated project.
2. Run `kiro-cli` once in a terminal and sign in.
3. Settings → Providers → Kiro: turn it on (it is on by default).

## Gotchas

- **Nothing shows at all** means `kiro-cli` isn't on your login shell's `PATH` (ClaudeBar also looks in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`). Kiro is skipped silently until it's found. A newly installed CLI can take up to two minutes to be noticed.
- **"No quota data found in Kiro CLI output"** means `kiro-cli` exited without printing a `Bonus credits: X/Y` line or a `Credits (X of Y covered in plan)` line. Run `kiro-cli`, then `/usage`, in a terminal to see what it prints (for example, a sign-in prompt).
- **"Command timed out after 30.0 seconds"** means `kiro-cli` didn't exit after `/usage` and `/quit`, for example because it's waiting at a prompt. Run it in a terminal and finish any sign-in or setup it asks for.
- **Bonus credits appear as a "Weekly" card.** They aren't a weekly window: the card shows how many are left and "Expires in N days".
- **The plan-credits reset date has no year.** Kiro prints `resets on MM/DD`; a date that has already passed this year is taken as next year.

## See also

[troubleshooting](../../troubleshooting.md) · [AWS Bedrock](../bedrock/README.md)
