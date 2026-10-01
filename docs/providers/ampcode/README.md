---
description: Track Amp Code free-tier dollars left and the individual credit balance by running `amp usage`. Use when setting up Amp or when it shows "No valid credit lines found".
---

# Amp Code

Shows what's left of your Amp credit: the **Free** allowance as a percentage (e.g. "$17.59/$20.00") and the **Individual** credit balance as a dollar amount. The account email comes from the same output.

## Setup

1. Install the Amp CLI so `amp` is on your PATH, and sign in with it. Check that `amp usage` prints your balance in Terminal.
2. Settings → Providers → Amp. It is on by default and has nothing to configure; it shows data as soon as `amp` is found.

## Gotchas

- **No reset time.** `amp usage` reports what's left, not when it resets. The Free allowance refills gradually (the CLI shows a rate such as "+$0.83/hour"), so there's no countdown for Amp.
- **The Individual balance has no percentage.** The CLI prints no total for it, so ClaudeBar shows it as "$X remaining" and colors it by the dollar amount.
- **"No valid credit lines found in amp usage output"** means the output didn't contain a `<name>: $X/$Y remaining` or `<name>: $X remaining` line. That happens when you're signed out, or when a new `amp` version changed its wording. Run `amp usage --no-color` yourself to see which.
- **"amp usage exited with code N"**: the CLI itself failed. Run it in Terminal to see the error.
- Other credit lines are shown too, under the name the CLI prints for them.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
