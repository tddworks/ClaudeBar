---
description: Let Claude Code push live session events to ClaudeBar through hooks, for Started/Finished notifications, the session indicator in the popover and menu bar, and the notch. Use when turning on session tracking or when it stays silent.
---

# Session Hooks

ClaudeBar can follow your Claude Code sessions as they happen. It adds hooks to Claude Code that POST each session event to a small server ClaudeBar runs on your Mac.

What you get:

- **Notifications**: "Claude Code Started: Session started in *project*" when a session starts, and "Claude Code Finished: *project* — Completed 3 tasks in 12m" (or "Session ended after 12m") when it ends.
- **Popover**: a session card at the top with the phase (Active, Agents Working, Stopped, Ended), subagent activity and completed tasks.
- **Menu bar**: a terminal glyph in front of the readout while Claude is working or subagents are running.
- **Notch**: the session activity described in [notch](../notch/README.md).

## Quick start

1. Settings → **Hooks** → turn on **Claude Code Hooks**.
2. The pane should then say "Hooks installed in ~/.claude/settings.json".
3. Start a new Claude Code session. Sessions that were already running pick up the hooks only after they restart.
4. Allow notifications for ClaudeBar if macOS asks. Without permission you still get the popover, menu bar and notch.

Turning the switch off removes ClaudeBar's hooks and stops the server.

## How it works

- **Hooks**: turning it on adds a hook for `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, `TaskCompleted`, `SubagentStart` and `SubagentStop` to `~/.claude/settings.json`. Hooks from other tools are kept. ClaudeBar recognizes its own entries by the `__claudebar_hook` marker in the command and only ever replaces or removes those.
- **The command**: each hook pipes Claude Code's event JSON to `curl -X POST http://localhost:<port>/hook` in the background, so it never slows Claude Code down. If ClaudeBar isn't running, the request fails silently.
- **Server and port**: ClaudeBar listens on the loopback interface only, on port **19847**, and accepts only `POST /hook`. On start it writes the port to `~/.claude/claudebar-hook-port`, which the hook reads (falling back to 19847), and deletes the file on stop.
- **Upgrades**: at launch, if hooks are installed, ClaudeBar reinstalls them, so hook events added in newer versions register without toggling the switch.
- **Its own probe is ignored.** ClaudeBar runs the Claude CLI to read your quota. Events from that probe (a working directory ending in `ClaudeBar/Probe`) are dropped, so they never show up as sessions or notifications.

## Gotchas

- **The switch flips back off with an error**: ClaudeBar won't overwrite a `~/.claude/settings.json` that isn't valid JSON. Fix the file, then turn the switch on again.
- **Port 19847 in use**: the server fails to start and the log records "Hook HTTP server failed". The `hook.port` key in `settings.json` is read but not used yet, so the port can't be changed. Free the port and restart ClaudeBar.
- **Stopped after every reply is normal**: `Stop` fires at the end of each turn, and your next prompt makes the session active again.
- **Nothing arrives**: check that the pane says installed, that `~/.claude/claudebar-hook-port` exists, and look for `[hooks]` lines in the [log](../../troubleshooting.md).

## See also

[Notch](../notch/README.md) · [menu bar](../menu-bar/README.md) · [troubleshooting](../../troubleshooting.md) · [settings.md](../../settings.md) for `hook.*`
