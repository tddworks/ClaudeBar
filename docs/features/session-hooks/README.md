---
description: Let Claude Code push live session events to ClaudeBar through hooks, for Started/Finished notifications, the session indicator in the popover and menu bar, and the notch. Use when turning on session tracking or when it stays silent.
---

# Session Hooks

ClaudeBar can follow your Claude Code sessions as they happen. It adds hooks to Claude Code that POST each session event to a small server ClaudeBar runs on your Mac.

What you get:

- **Notifications**: "Claude Code Started: Session started in *project*" when a session starts, and "Claude Code Finished: *project* — Completed 3 tasks in 12m" (or "Session ended after 12m") when it ends.
- **Popover**: a session card at the top with the state (Working, Agents working, Needs you, Done, Ended — the [notch](../notch/README.md)'s words), subagent activity and completed tasks. With several sessions running, the one card keeps a line of coloured squares and a count (*1 needs you · 2 working · 5 done*), a row for each session that isn't Done, the one that most needs you first, and the Done ones behind ▾, one row per repo with when it finished.
- **Menu bar**: a terminal glyph in front of the readout while Claude is working or subagents are running. With several sessions it follows the one that most needs you: Needs you first, then Agents working, then Working, then Done.
- **Notch**: the session activity described in [notch](../notch/README.md).

## Quick start

1. Settings → **Hooks** → turn on **Claude Code Hooks**.
2. The pane should then say "Hooks installed in ~/.claude/settings.json".
3. Start a new Claude Code session. Sessions that were already running when you turned hooks on pick them up only after they restart.
4. Allow notifications for ClaudeBar if macOS asks. Without permission you still get the popover, menu bar and notch.

Turning the switch off removes ClaudeBar's hooks and stops the server.

## How it works

- **Hooks**: turning it on adds a hook for `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, `StopFailure`, `TaskCompleted`, `SubagentStart` and `SubagentStop` to `~/.claude/settings.json`. Hooks from other tools are kept. ClaudeBar recognizes its own entries by the `__claudebar_hook` marker in the command and only ever replaces or removes those.
- **The command**: each hook pipes Claude Code's event JSON to `curl -X POST http://localhost:<port>/hook` in the background, so it never slows Claude Code down. It adds an `X-ClaudeBar-Pid` header with Claude Code's process ID (`CLAUDE_PID`), which is how ClaudeBar notices a session whose process died. If ClaudeBar isn't running, the request fails silently. Sessions that ClaudeBar spawned itself (quota polls) carry a `CLAUDEBAR_PROBE` marker in their environment, and the command exits before POSTing when it sees one — polling never fires session notifications.
- **Server and port**: ClaudeBar listens on the loopback interface only, on port **19847**, and accepts only `POST /hook`. On start it writes the port to `~/.claude/claudebar-hook-port`, which the hook reads (falling back to 19847), and deletes the file on stop.
- **Upgrades**: at launch, if hooks are installed, ClaudeBar reinstalls them, so hook events added in newer versions register without toggling the switch.
- **Its own probe is ignored.** ClaudeBar runs the Claude CLI to read your quota. Events from those probe sessions are dropped — ClaudeBar marks the sessions it spawns (`CLAUDEBAR_PROBE`) and also filters the working directory ending in `ClaudeBar/Probe` — so they never show up as sessions or notifications.

## Gotchas

- **The switch flips back off with an error**: ClaudeBar won't overwrite a `~/.claude/settings.json` that isn't valid JSON. Fix the file, then turn the switch on again.
- **Port 19847 in use**: the server fails to start and the log records "Hook HTTP server failed". The `hook.port` key in `settings.json` is read but not used yet, so the port can't be changed. Free the port and restart ClaudeBar.
- **A session that was killed lingers for up to 30 seconds**: a crash or a force-quit terminal sends no `SessionEnd`. The hook tells ClaudeBar which Claude Code process it runs in, and every 30 seconds ClaudeBar ends sessions whose process is gone. Hooks installed by an older ClaudeBar don't send it; ClaudeBar reinstalls them at launch, and sessions started after that are covered.
- **A session stuck on Working after the Mac slept**: a turn that ends in an error (the connection dropped during sleep) reports `StopFailure`, not `Stop`. ClaudeBar listens to it since this version; hooks installed by an older ClaudeBar are reinstalled at launch.
- **Done after every reply is normal**: `Stop` fires at the end of each turn, and your next prompt makes the session Working again. A session that has just opened is Done too, until its first prompt.
- **Working after you interrupted a turn**: Claude Code fires no `Stop` when you interrupt with Esc or Ctrl-C, so the session stays Working until your next prompt.
- **Nothing arrives**: check that the pane says installed, that `~/.claude/claudebar-hook-port` exists, and look for `[hooks]` lines in the [log](../../troubleshooting.md).

## See also

[Notch](../notch/README.md) · [menu bar](../menu-bar/README.md) · [troubleshooting](../../troubleshooting.md) · [settings.md](../../settings.md) for `hook.*`
