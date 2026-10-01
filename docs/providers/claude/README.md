---
description: Track Claude 5-hour session, weekly and per-model (Opus, Sonnet, Fable) limits plus Extra Usage spend, via `claude /usage` or the OAuth usage API. Use when setting up Claude or when it shows an error.
---

# Claude

Shows your Claude Code 5-hour session and weekly limits, any model-specific weekly limits (Opus, Sonnet, Fable), Extra Usage spend when it's turned on, and today's cost and tokens from your local session logs. Pay-as-you-go API accounts get a cost card instead of quota bars.

## Setup

1. Install [Claude Code](https://claude.ai/code) and run `claude` once in a terminal to sign in (`claude login`).
2. Settings → Providers → Claude: turn it on (it is on by default).
3. Optional: in the same pane, **Claude Configuration → Probe Mode** picks CLI or API.

## Probe modes

| Mode | Needs | Pick it when |
|---|---|---|
| CLI (default) | `claude` on your login shell's `PATH` | Almost always; works with any sign-in method |
| API | OAuth credentials from `claude login` (Keychain or `~/.claude/.credentials.json`) | CLI mode is slow, prompts, or can't see your subscription |

Each mode falls back to the other when it fails. In API mode, **CLI fallback** (on by default) controls whether `claude /usage` runs when the API can't answer; turn it off if running the CLI causes prompts (e.g. SSH key prompts) and you'd rather see the error. A rate-limit error never triggers the fallback, because the CLI hits the same backend.

## Permissions

- **Keychain.** On macOS, `claude login` stores its token only in the Keychain item `Claude Code-credentials`. API mode reads it through Apple's `/usr/bin/security` tool, so it normally doesn't show a Keychain prompt. When ClaudeBar refreshes an expired token it writes the new one back to the same place.
- **Folder trust.** CLI mode runs `claude` in `~/Library/Application Support/ClaudeBar/Probe`. If Claude Code asks whether you trust that folder, ClaudeBar answers the prompt, and if that fails it marks the folder as trusted in `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`) and tries again.

## Gotchas

- **`claude setup-token` alone isn't enough.** The `CLAUDE_CODE_OAUTH_TOKEN` it creates can only be used for inference and can't read quota. ClaudeBar uses a full `claude login` credential when one exists, and removes that variable when it runs the CLI.
- **Slow SessionStart hooks can make Claude look unavailable.** ClaudeBar's probe runs `claude /usage` and waits up to 20 seconds for the Usage screen. It opens only after Claude Code has finished its own startup, so hooks that take longer than that (or a very busy machine) make the probe time out even though you're working in Claude fine. ClaudeBar then falls back to the usage API, so you only see "Claude Unavailable" if that fails too. Run `claude` in a terminal and watch for `(running SessionStart hooks… N/M)`; if that counter is still climbing after ~15 seconds, that is the cause. Speeding up or trimming those hooks fixes it, and API probe mode skips the CLI entirely.
- **API mode refreshes at most every 15 minutes.** Anthropic throttles its usage endpoint hard (after a 429 it can refuse requests for up to an hour), so results are cached for 15 minutes and background refresh can't go faster than that. After a 429, ClaudeBar waits for the `Retry-After` time (5 minutes if none is given) and shows "Rate limited. Retrying …".
- **"Claude usage data did not finish loading".** `/usage` shows a loading placeholder before its quota bars arrive. If it never gets past that, the usage endpoint is probably rate limited. Wait a moment, or switch modes.
- **Max or Pro billed through Apple showing "The Claude CLI did not see this account's subscription".** On some subscriptions `/usage` reports API billing instead of a plan — either the cost panel on its own, or "only available for subscription plans". ClaudeBar sees from `~/.claude.json` that you have a subscription, so it tries the API rather than showing $0.00. If the API also fails, run `claude login` again or switch to API mode.
- **"Authentication required" when you're already signed in** usually means the Keychain read failed. The log records the `security` exit status. See [troubleshooting](../../troubleshooting.md).
- **Account email and organization come from `~/.claude.json`**, because Claude CLI v2.1.79+ no longer shows them on the Usage tab.
- **Daily cost and token cards** read `~/.claude/projects/*/*.jsonl`. They're only calculated when the popover is open, not during background refreshes.
- **Share Claude Code** (guest passes) only appears for Max accounts.
- **Claude API Budget** in the same pane only applies to pay-as-you-go API accounts, not to Max or Pro Extra Usage.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Notch](../../features/notch/README.md)
