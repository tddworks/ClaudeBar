---
description: Track Amp Code free-tier dollars left and the individual credit balance by running `amp usage`. Use when setting up Amp or when it shows "No valid credit lines found".
---

# Amp Code

Shows what's left of your Amp credit: the **Free** allowance as a percentage (e.g. "$17.59/$20.00") and the **Individual** credit balance as a dollar amount. The account email comes from the same output.

## Setup

1. Install the Amp CLI so `amp` is on your PATH, and sign in with it. Check that `amp usage` prints your balance in Terminal.
2. Settings → Providers → Amp. It is on by default and has nothing to configure; it shows data as soon as `amp` is found.
3. A second Amp account: **Accounts → Add Account** asks for that account's own access token, kept in your Keychain. ClaudeBar runs `amp usage` with it as `AMP_API_KEY`; your own sign-in is never used for it.

## Gotchas

- **No reset time.** `amp usage` reports what's left, not when it resets. The Free allowance refills gradually (the CLI shows a rate such as "+$0.83/hour"), so there's no countdown for Amp.
- **The Free allowance shows dollars of its ceiling** ("$17.59 of $20"); the Individual balance has no total, so it shows "$X remaining" and no percentage.
- **"No valid credit lines found in amp usage output"** means the output didn't contain a `<name>: $X/$Y remaining` or `<name>: $X remaining` line. That happens when you're signed out, or when a new `amp` version changed its wording. Run `amp usage --no-color` yourself to see which.
- **"`amp` exited with code N"**: the CLI itself failed. Run `amp usage` in Terminal to see the error.
- Other credit lines are shown too, under the name the CLI prints for them.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
