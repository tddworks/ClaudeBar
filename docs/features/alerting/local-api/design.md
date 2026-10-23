---
description: Contributor design for the local API and MCP server — a loopback-only, read-only HTTP surface over the Monitor, its three questions asked twice (JSON and MCP tools), and the laws that keep the wire from growing a second brain.
---

# Local API & MCP server — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to a new kind of
> surface: one that is not on this screen at all. The menu bar, the popover and
> the notch answer Mia's glance; this answers the question an **agent** asks
> before it starts working. Users: [README.md](README.md).
>
> **Status: BUILT** ([#618](https://github.com/tddworks/ClaudeBar/pull/618)).

## The person and the moment

Mia's agent (Claude Code, opencode) is about to start a two-hour task. Mia is
not looking at the menu bar — the agent is. It wants to ask, before it burns
the window: **"will I run out mid-task? which login should I use?"** The
answers already exist — the Monitor holds them, refreshed on its own cadence.
What is missing is a door: a way for another process on this Mac to ask.

Raycast, a shell script and a launcher ask the same thing, in plainer words.
[status.json](../../alerting/touch-bar/README.md) answers push-shaped needs
(a file, rewritten); an ask-shaped need wants a question, and `claudebar://`
[URL schemes](../../app/url-schemes/README.md) mutate or open windows. What
nobody has yet is **read**.

## Where it lives

The question is the *All* page's — "can I start, and on which login?" —
asked by another process instead of a person. So the feature adds no
reading of its own: it reads **`Overview(monitor)`**, the popover's read,
and is a **destination** for it. A pull surface that only reads the Monitor
and never changes state is the same kind of thing as the status export, so
it sits in **Alerting** beside it ([CANONICAL §7](../../../architecture/CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)):
`Sources/Infrastructure/Alerting/LocalAPI`, its tests beside it, this
document under `docs/features/alerting/`. The journey moment is
[USER_JOURNEYS #21](../../../architecture/USER_JOURNEYS.md#beyond-the-menu-bar).

```text
QuotaMonitor ─▶ Overview(monitor) ─▶ LocalAPIRouter encodes ─▶ JSON · MCP text
                 (Domain/Monitoring)   (Infrastructure/Alerting/LocalAPI)
```

## What is true

The Monitor is the single source of truth for provider state. This feature
adds **no state, no refresh, no rule about quotas**. Every fact it prints is
one `Overview` already holds: the cards in pill order, each card's status
(the healthiest login's, `nil` without numbers), the quota the ring shows and
the login it reads, the product's best login and the one in use. Everything
it says, the *All* page could have said a second earlier, and the two never
disagree: the lowest `/status` names is the ring the popover leads with.

Because it holds nothing, its whole design is two moves: **read the
Overview**, and **encode it twice** — once as plain HTTP JSON, once as MCP
tools. The two skins answer with the *same* payloads; there is no second
system.

## The laws, one owner each

| Law | Owner |
|---|---|
| the API answers only what the Monitor already knows: it never refreshes, never decides, never holds a number of its own | `Overview(monitor)` — the router only encodes it |
| `/status`'s lowest is the quota the popover leads with: each product read by its healthiest login, then the one with the most left — a product's logins are interchangeable (CANONICAL §5); never the least across every login | `Overview.tightestCard` · `OverviewCard.login` |
| a status reads the person's `StatusPolicy`, hidden quotas left out — the same status every surface prints; a login, or a whole lineup, with no numbers yet reports `status: null`, never *healthy* | `OverviewCard.Login.status` · `Overview.status` |
| `providers` counts **products**, the cards — never logins | `Overview.cards` |
| which login has the most left (`best`) and which one new sessions start with (`inUse`) are the product's answers, repeated | `Accounts.best` · `InUse` (read into `OverviewCard`) |
| a quota with no share reports no percentage — a balance with no ceiling is never dressed as 100%, and two currencies are never divided | `UsageQuota.percentLeft` · `isBalance` |
| **read-only**: the route table is closed and holds no mutation; pause, switch, refresh and settings stay behind the person's hands (URL schemes, the Settings window) | `LocalAPIRouter` |
| the socket exists only while the person's switch is on; off means no listener, not a quiet one | `LocalAPISettingsRepository` · the composition root (`ClaudeBarApp`) |
| **loopback only**: the listener binds `127.0.0.1`, and a connection whose peer is not a loopback address is cancelled before a byte is read; a request whose `Host` or `Origin` names another host is refused with *403* — a rebinding browser may not read | `LocalAPIServer` · `LocalAPIRouter` |
| only GET and POST are served; anything else is refused with *405* and an `Allow` header. Bodies are capped (1 MiB) and header blocks (64 KiB) — an oversized or unparseable request is refused, never half-served | `LocalAPIRequestParser` · `LocalAPIRouter` |
| one MCP tool per question, and each tool answers with the same payload its HTTP route answers — the tool list is the route list | `LocalAPIRouter` (the tool table it hands `MCPKernel`) |
| the protocol handling is socket-free: bytes in, values out. Every decision on the wire is testable without a socket | `LocalAPIRequestParser` · `LocalAPIResponseSerializer` · `MCPKernel` · `LocalAPIRouter` |

### Why read-only

A window onto the Monitor is safe to hand to any local process: the worst it
can leak is what the menu bar already shows. A window that could pause a
login, switch the folder new sessions start on, or kick a refresh would let
any script change Mia's setup with no confirmation — that is what
`claudebar://` is for, and it asks nothing less than a person clicking. So
the door opens one way, and the design doc is where that is said, not a
comment in a handler.

### Why default off

A listener is a surface every process on this Mac can reach, and this one
speaks to agents — an audience that grows without Mia re-reading release
notes. The repo's own precedent: `hook.enabled` and `notify.enabled` default
to off, and Notify *can never* come up on, because it leaves the Mac. The
local API stays on this Mac, but it is still a door; Mia turns it on in
Settings → **Local API** when she wants agents to ask, and the pane prints
the exact `claude mcp add` line for the port it is actually on. Turning it
on is a deliberate act by the person who will be asked about it.

### The port: 19848

One fixed, documented default: **19848** (`LocalAPIServer.defaultPort`),
with `127.0.0.1` understood.
Chosen to sit beside the hook server's **19847** — ClaudeBar's two local
ports are neighbours, one number apart, and a person who has typed one can
guess the other. Not 3000/8080/9000: the memorable low ports are the ones
every other dev tool already fights over, and losing that fight on a random
machine would make the documented URL lie.

If 19848 is taken (a second ClaudeBar — a debug copy beside the installed
app — or any other process), the server does **not** move silently to a port
no URL names: it takes an auto-assigned port, writes the real number to
`~/.claudebar/api-port`, and the Settings pane builds its `claude mcp add`
line from the port file, so the line it prints is the line that works. A
launcher that wants the real port reads the file, as the hook installer's
scripts do. The file is written on every start — default port or not — and
removed on stop, so a file that exists never lies and a pane never prints a
line for a server that is off. It is the same decision the hook server
already made, so both use one type: `PortFile`, a path with write, read and
remove (`PortFile.hooks` is `~/.claude/claudebar-hook-port`,
`PortFile.localAPI` is `~/.claudebar/api-port`). The two listeners stay two
for now; one listener can follow when the hooks next change.

## The words (the JSON contract)

One word per question, the same nouns the screens print: `status` (HEALTHY ·
WARNING · CRITICAL · DEPLETED), `percentLeft`, `resetsAt`, `forecast`,
`best` (*switch to work*), `inUse` (IN USE). Dates are ISO 8601. An optional
field with nothing to say is left out of the JSON, which a client reads as
`null`; a `null` means what it means on screen — a balance has no percentage, a quota with no
forecast has no line, and a login with no numbers yet has no `status` (the
card says *Syncing* or *Unavailable*, never HEALTHY).

```text
GET  /                    → this index: the routes, the MCP path
GET  /status              → StatusSummary    one line: the ring the popover leads with, the overall status
GET  /providers           → ProvidersReport  every card's logins: quotas, status, best, inUse
GET  /forecast            → ForecastReport   every quota that has a forecast line
GET  /usage/days?n=30     → UsageDaysReport  per login, day by day (n clamped to 1...365)
POST /mcp                 → JSON-RPC 2.0     initialize · tools/list · tools/call
```

Anything else: `404` with `{"error": "not found"}`; a known path with the
wrong method: `405` + `Allow`. Only GET and POST exist.

## The pieces

```text
                          curl · Raycast · claude mcp
                                     │ bytes
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│ LocalAPIServer (Infrastructure)   THE ADAPTER — NWListener bound to  │
│                                   127.0.0.1; peer check; bytes ⇄    │
│                                   values; one request per connection │
└───────────────┬──────────────────────────────────────────────────────┘
                │ LocalAPIRequest
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ LocalAPIRouter (Infrastructure)   THE ROUTES — the closed table:     │
│   ├─ payloads encoded from one read   404 · 405 · the four answers   │
│   └─ MCP: the tool table → MCPKernel  (one tool per route)           │
└───────────────┬──────────────────────────────────────────────────────┘
                │ read: @MainActor () -> Overview
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Overview(monitor) (Domain)        the All page's read: cards, each   │
│                                   card's login, ring, status, best,  │
│                                   inUse; each login's usageHistory   │
└──────────────────────────────┬───────────────────────────────────────┘
                               ▼
                          QuotaMonitor  (the tree — unchanged)
```

| Piece | Where | One job | Changes when |
|---|---|---|---|
| `LocalAPISettingsRepository` | `Domain/Alerting` | the switch's port (beside `HookSettingsRepository`) | the switch grows company |
| `Overview` · `OverviewCard` | `Domain/Monitoring` ([all-providers](../../monitoring/all-providers/design.md)) | the read: `status`, `tightestCard`, each card's `login`, `best`, `inUse`, each login's `source` and `usageHistory` | the *All* page's question changes |
| `LocalAPIRequest` · `LocalAPIResponse` | `Infrastructure/Alerting/LocalAPI` | the wire as values: method, path, query, headers, body | a header or the query grows a field the routes need |
| `LocalAPIRequestParser` · `LocalAPIResponseSerializer` | same | bytes ⇄ values, with the caps and the refusals | the HTTP dialect changes (chunked, keep-alive) |
| `StatusSummary` · `ProvidersReport` · `ForecastReport` · `UsageDaysReport` | same | **the JSON contract** — each encodes an `Overview`; no rule of its own | a payload field is added or renamed |
| `LocalAPIRouter` | same | the closed route table; 404/405; the MCP tool table | a route is added (a deliberate edit) |
| `MCPValue` · `MCPKernel` | `Infrastructure/Alerting/LocalAPI/MCP` | JSON-RPC 2.0 in values; initialize, tools/list, tools/call | the MCP surface grows (SSE, sessions) |
| `LocalAPIServer` | same | the only socket: bind loopback, peer check, receive → answer → send → close; the default port | the transport changes |
| `PortFile` | `Infrastructure` | a port number in a file a script reads — the hooks' and the API's | where a port is told changes |
| `LocalAPIPane` | `App/Views/SettingsWindow` | the switch, and the lines to copy while it is on | the copy changes |
| `ClaudeBarApp` | `App` | the composition root: starts and stops the server with the switch, hands the router `{ Overview(monitor) }` | never, for a route |

There is no port between the router and the Monitor: the router is handed a
closure that reads the Overview on the main actor, and its tests hand it an
`Overview(cards:)` built by hand. The one port is at the outside world — the
socket.

## The flows

**A curl.** bytes arrive → the server rejects any non-loopback peer, reads
until the request is whole (or the caps refuse it) → `LocalAPIRequestParser` makes
a value → `LocalAPIRouter` looks the route up → it hops to the main actor and
reads `Overview(monitor)` → the payload encodes it → `LocalAPIResponseSerializer`
makes bytes → send, close. One request per connection; no keep-alive to time out.

**`claude mcp add --transport http claudebar http://127.0.0.1:19848/mcp`.**
The client POSTs `initialize` → `MCPKernel` answers
`protocolVersion` (`2025-06-18`, echoed when the client names one we serve),
`capabilities: {tools: {}}`, `serverInfo: {name: "claudebar"}`. The client's
`notifications/initialized` carries no id — a notification gets `202 Accepted`
and nothing else. `tools/list` names the four tools; `tools/call` runs the
same payload builders and returns `content: [{type: "text", text: <the JSON>}]`.
Stateless: no session id, no stream. A tool that runs is never a protocol
error — an unknown *tool* is `-32602`, an unknown *method* is `-32601`, and a
body that is not JSON is `-32700` at `400`.

**The switch.** Settings → Local API → on: the pane saves `api.enabled`,
posts `.localAPISettingsChanged`, and the composition root starts the server
(the same notification→closure path the hooks toggle uses). Off: the listener
is cancelled and the port file removed. At launch the composition root starts
it when the switch is on. When the socket is ready the server has written the
port file — the real number, default or not — and the composition root
announces it; the pane re-reads the file then, so the lines it shows and
copies name the port that actually answers.

**Usage days.** An explicit ask, like a popover opening: each card login's
`usageHistory` (`account.usageHistory`, carried on the Overview) is asked for
`.last(n)` days. A login with no history has no series. Never in the
background; the Monitor's cadence is untouched.

## Tests

Swift Testing, Chicago school:

- Domain, `OverviewTests` (a neutral fixture; a real Monitor over stubbed
  data sources where the Monitor matters) — the card's `login` is the one its
  ring reads; `tightestCard` is the product the popover leads with, each read
  by its healthiest login, never the emptiest login of the lineup; `status`
  is `nil` until a card has numbers; `best` and `inUse` repeat the product's
  answers.
- Infrastructure, `Tests/InfrastructureTests/Alerting/LocalAPI` — the kernels
  are fed raw bytes and values, no socket:
  - `LocalAPIRequestTests` — a real request's bytes become a value; bad request
    lines, oversized bodies and header blocks are refused, and so is a
    `Content-Length` that cannot be read; a value becomes bytes a client can
    read.
  - `LocalAPIPayloadTests` — the JSON contract over a hand-built `Overview`:
    a share, a balance with no percentage, a capped money quota, a forecast
    that runs out, one that lasts, a login with no numbers (`status: null`),
    products counted as products, a day series read from a login's history.
  - `LocalAPIRouterTests` — the closed table: 200s, `404`, `405` + `Allow`,
    `403` for a `Host` or `Origin` from another host, `n` clamped, and a full
    bytes→router→bytes round trip.
  - `MCPKernelTests` — the handshake, the notification's silence, the tool
    list, a tool call's text content, the three error codes, the version echo.
- `PortFileTests` — written, read back, removed; a file with no number reads
  nothing.
- `api.enabled` reads false before it is set and is remembered when turned
  on — beside the hook settings' tests
  (`Tests/InfrastructureTests/Settings/JSONSettingsRepositoryProviderTests`),
  and the Settings search finds Local API by `mcp`/`localhost`
  (`Tests/AppTests/Settings/SettingsSectionSearchTests`).

## What this is not (deferred, on purpose)

| Not in it | Why |
|---|---|
| an auth token option | loopback only; the socket dies with the Mac's own processes. When a real need arrives it is one header check in the router |
| SSE / streaming | the minimum that makes `claude mcp add` + one tool call work is one JSON response per request; a stream adds a second transport to test for nothing the questions need |
| resource subscriptions, `resources/*`, prompts | the tools *answer questions*; a subscription would make the server hold state — the one thing this feature exists to avoid |
| any write action | see [Why read-only](#why-read-only) |
| a standalone CLI binary | the app is already running and refreshed; a second process would need its own refresh loop — a second source of truth |
| a port setting | a moved port breaks every saved URL; the default is chosen once and documented. The port file covers the collision case |
| keep-alive, chunked encoding, CORS | one request per connection is enough for curl and every MCP client; CORS would invite browsers to a surface meant for agents and launchers |

## Considered and rejected

- **Serving from `status.json` instead.** It is push-shaped, gated by the
  Touch Bar switch, and holds no forecast, no best login, no usage history.
  A question wants an answer, not a file to poll.
- **Reading the usage snapshot from disk.** The Monitor is the single source
  of truth; a second reader would disagree with the popover the moment a
  refresh lands.
- **A reading of its own between the wire and the Monitor.** An earlier
  draft grouped the lineup by product and picked the lowest quota itself,
  behind two protocols; its lowest was the emptiest login of the lineup,
  where the popover reads each product by its healthiest login, and it called
  a login with no numbers *healthy*. The question is the *All* page's, so the
  answer is `Overview`'s.
- **MCP over stdio.** `claude mcp add --transport http` was the named
  moment, and a stdio child process would put a second ClaudeBar-shaped
  process on Mia's machine for every client.

## Is it easy to change?

| Someone wants… | They change |
|---|---|
| a new read (say, cost this month) | the fact on `Overview` if it isn't there, a payload value, a route row and one tool row |
| auth for out-of-process callers | the deferred token: one check at the top of `answer(_:)` |
| SSE for tool progress | a second response path in the server behind the same kernel |
| the same API for ClaudeBar for Windows | the kernels are Foundation-only; only `LocalAPIServer` is platform work |
