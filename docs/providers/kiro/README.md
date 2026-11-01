---
description: Track Kiro monthly plan credits and bonus credits by asking `kiro-cli` for its usage. Use when setting up Kiro or when it shows nothing or "No quota data found in Kiro CLI output".
---

# Kiro

Shows your Kiro plan credits for the month (with the date they reset) and any bonus credits (with the days until they expire).

## Setup

1. Install the Kiro CLI: `curl -fsSL https://cli.kiro.dev/install | bash`. **Don't** use `pip install kiro-cli` or `uv tool install kiro-cli`: the `kiro-cli` package on PyPI is an unrelated project.
2. Run `kiro-cli` once in a terminal and sign in.
3. Settings → Providers → Kiro: turn it on (it is on by default).
4. A second Kiro account: sign in to it with a separate home folder (`HOME=/path/to/folder kiro-cli`), then **Accounts → Add Account** and choose that folder. ClaudeBar runs `kiro-cli` with that folder as its home; your own sign-in stays untouched, and removing the account leaves the folder where it is.

## Gotchas

- **Nothing shows at all** means `kiro-cli` isn't on your login shell's `PATH` (ClaudeBar also looks in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`). Kiro is skipped silently until it's found. A newly installed CLI can take up to two minutes to be noticed.
- **"No quota data found in Kiro CLI output"** means neither way of asking returned credits. ClaudeBar first asks the Kiro engine directly (`kiro-cli acp`, the same request as the `/usage` screen); a kiro-cli too old for that, or an engine that answers with no usage, is read from `/usage` instead. Run `kiro-cli`, then `/usage`, in a terminal to see what it shows (for example, a sign-in prompt).
- **"Timed out"** means `kiro-cli` didn't answer in time, for example because it's waiting at a prompt. Run it in a terminal and finish any sign-in or setup it asks for.
- **Bonus credits have their own card** showing how many are left and "Expires in N days". With more than one grant, each has its own card named after the grant. They are a grant that runs out, not a window that refills, so there is no pace for them.
- **The plan-credits reset date** is the day your billing cycle resets. An older kiro-cli prints it with no year (`MM/DD`); a date that has already passed this year is taken as next year.
- **An added login needs a folder of its own.** The default login's folder and another listed login's are refused, `~` included. A path you type with `~` is saved as the full folder, because the CLI can't expand it.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [AWS Bedrock](../bedrock/README.md)
