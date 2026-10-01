---
description: Show quota and live Claude Code session state (working, subagents, needs you, done) in the MacBook notch, or a virtual notch on other displays. Use when turning on Notch Live Activity or when it shows nothing.
---

# Notch Live Activity

ClaudeBar draws a small live status in the MacBook notch, like a Dynamic Island for your quota and your Claude Code session. On a display without a notch it draws a virtual one at the top centre. It shows only while it has something to report, and hovering over it opens a panel with more detail.

Mockup: [notch-live-activity.html](../../mockups/notch-live-activity.html)

## Setup

1. **Settings → General → Notch Live Activity**. It's off by default.
2. For session states, also turn on **Settings → Hooks → Claude Code Hooks** ([session hooks](../session-hooks/README.md)). That installs ClaudeBar's hooks into Claude Code, which report when a session starts, finishes a turn or waits for you. Without hooks, the notch shows quota only.

The notch follows the provider that's selected in the popover. Pick a different provider there to watch a different quota.

## What it shows

When several states apply at once, the one that needs you most wins:

| Priority | State | Notch shows | Clears when |
|---|---|---|---|
| 1 | **Needs you**: Claude Code is waiting for a permission or an answer | ⚠︎ "Needs you" and the prompt text | Claude Code carries on and finishes the turn, you send a new prompt, or the session ends. Never times out |
| 2 | **Done**: a turn or session just finished | ✓, the repo, the task count and duration | After 4 seconds |
| 3 | **Quota low**: a quota of the selected provider is under 20% left | That quota's name, % left, bar and reset time | The quota recovers |
| 4 | **Agents working**: subagents are running | The repo, "N agents", elapsed time | The subagents finish |
| 5 | **Working**: Claude Code is on a turn | A green dot, the repo, elapsed time | The turn ends |
| 6 | **Quota glance**: nothing else is happening | The selected provider's lowest quota: % left, bar, reset time | — |

The session states also show the lowest quota at the right, so you don't lose sight of how much is left.

If the selected provider has no data yet and no session is running, the notch hides.

### Hover panel

Move the pointer onto the notch to open the panel:

- up to three sessions: the running one, plus any that finished in the last 10 minutes
- the selected provider's three most-used quotas, with reset times
- today's usage, if the provider reports daily usage
- **Refresh quotas**, which refreshes only the selected provider
- **Snooze 30m**, which hides the notch for 30 minutes. **Needs you** still appears while snoozed.

Move the pointer away to close the panel.

## Gotchas

- **Only session states need hooks.** If the notch shows quota but never "Working", check **Settings → Hooks**. The hooks are installed in Claude Code's own settings file.
- **One session at a time.** ClaudeBar follows the most recently started Claude Code session. Starting a second one moves the notch to it and puts the first in the finished list.
- **Which display.** The notch goes on the first display with a physical notch. Without one, it goes on the main display as a virtual notch the height of the menu bar.
- **It never takes focus.** Your terminal stays active, and clicks outside the drawn notch go to the menu bar behind it.
- **Not on the lock screen.** ClaudeBar uses only public window APIs, so it can't draw there.
- **It shows up in screen recordings and screenshots** like any other window.
- **Always black.** The notch copies the physical cutout in every theme. Only its status colours follow **Settings → Appearance**.

## See also

- [design.md](design.md): the research and architecture, prior art (boring.notch, DynamicNotch), and why there's no private API
- [Session hooks](../session-hooks/README.md): what the hooks install and how to check them
- [Notify!](../notify/README.md): the same quota on your iPhone Lock Screen
