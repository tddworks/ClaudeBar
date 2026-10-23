---
description: Ask ClaudeBar what it knows — a local, read-only API on 127.0.0.1 for agents (Claude Code, opencode) and launchers (curl, Raycast): will I run out mid-task, which login should I use. Use when wiring an agent to quotas or when a request fails.
---

# Local API & MCP server

ClaudeBar can serve its quota data on your Mac's loopback interface, read-only, so anything on this Mac can ask before a big task: **will I run out mid-task? which login should I use?** Agents (Claude Code, opencode) ask over [MCP](#mcp-claude-code-opencode); launchers and scripts ask with [curl](#plain-http-curl-raycast-scripts).

The answers are the ones the popover would give — the same statuses, the same forecast, updated on the same refresh. Nothing can be changed through it: no pause, no switch, no refresh. **Read-only, on 127.0.0.1 only** — nothing outside your Mac can reach it.

## Turn it on

Settings → **Local API** → *Serve quota data on this Mac*. The pane shows the port and the two lines to copy. It stays off until you turn it on.

The default port is **19848**. If something else on your Mac already holds it, ClaudeBar takes the next free port and writes the real number to `~/.claudebar/api-port` — the pane always shows the line that works right now. The file is written whenever the switch is on and removed when it is off.

## Plain HTTP (curl, Raycast, scripts)

```bash
# One line: the worst quota and the overall status
curl -s http://127.0.0.1:19848/status

# Every watched login: quotas, status, which one has the most left ("best"),
# which one new terminal sessions start with ("inUse")
curl -s http://127.0.0.1:19848/providers

# Every quota that has a forecast line — runs out before it resets, or lasts
curl -s http://127.0.0.1:19848/forecast

# Daily usage, per login — last 30 days (any n from 1 to 365)
curl -s "http://127.0.0.1:19848/usage/days?n=30"
```

`GET /status` answers like this:

```json
{
  "status" : "warning",
  "summary" : "34% left · warning",
  "lowest" : {
    "provider" : "codex",
    "login" : "codex",
    "name" : "Codex",
    "quota" : "Session",
    "key" : "session",
    "percentLeft" : 34,
    "resetsAt" : "2026-10-22T15:00:00Z",
    "resetsInMinutes" : 214
  },
  "providers" : 2,
  "updatedAt" : "2026-10-22T11:26:00Z"
}
```

`lowest` is the quota the popover's *All* page leads with: each product is read by its login with the most room, so one empty login never stops an agent that could switch. `providers` counts products, not logins.

A `null` means what it means on screen: a prepaid balance has no `percentLeft`, a quota with no pace has no forecast, and a login with no numbers yet has no `status` (it is still syncing, or it failed). Dates are ISO 8601.

## MCP (Claude Code, opencode)

```
claude mcp add --transport http claudebar http://127.0.0.1:19848/mcp
```

Four tools, one per question:

| Tool | Answers |
|---|---|
| `quota_status` | The one line: worst quota, overall status |
| `providers` | Every watched login: quotas, `best`, `inUse` |
| `forecast` | Which quotas run out before they reset |
| `usage_days` | Daily usage per login, `{ "n": 30 }` |

The server is stateless streamable HTTP: `initialize`, `tools/list`, `tools/call`, JSON responses, no session id. Handshake and calls work with any MCP client that speaks the transport.

## What it will not do

No writes — the API cannot pause a login, switch the login new sessions start with, or trigger a refresh; those stay in the popover, Settings and the [`claudebar://` URL schemes](../../app/url-schemes/README.md). No access from other machines — the listener is bound to `127.0.0.1` and refuses any peer that is not your Mac. Only `GET` and `POST` are served; anything else is refused.

## Not working?

| Symptom | Fix |
|---|---|
| Connection refused | The switch is off (Settings → Local API), or ClaudeBar is not running. The port may have moved: read `~/.claudebar/api-port` |
| "Address already in use" in the log | Another process held 19848 at startup; ClaudeBar moved to a free port — use the port file's number |
| An MCP client can't connect | Check the port in `~/.claudebar/api-port`, then `claude mcp remove claudebar` and add it again with the port the pane shows |
| Quotas are empty | The API reads the Monitor, it never refreshes — open the popover once, or wait for the background refresh |

## See also

[Troubleshooting](../../../troubleshooting.md) · [status.json for Touch Bar and scripts](../../alerting/touch-bar/README.md) · [URL schemes](../../app/url-schemes/README.md)
