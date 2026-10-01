---
description: Contributor research behind publishing to Notify!. Covers the gateway API and its id namespaces, the payload rules, publish cadence and keep-alive, error recovery, privacy, and the designs that were rejected.
---

# Notify!: design

User guide: [README.md](README.md).

ClaudeBar already knows every quota worth knowing, and the phone is where the user actually looks. [Notify!](https://getnotifyapp.com) already exists, runs on Mac and iOS and reaches anything else through web push, and has a documented gateway API, so ClaudeBar can put a quota on a Lock Screen and a Home Screen without shipping an iOS app of its own.

---

## The problem

Every surface ClaudeBar has is on the Mac, and every one of them needs the Mac awake and in front of you.

| Surface | Failure mode |
|---|---|
| **16 px status item** | One number, on a screen you have to be looking at. Gone the moment the lid closes. |
| **Popover** | A click on a target you have to aim for, on a machine you have to be sitting at. |
| **User notifications** | Transient, and delivered to the Mac. Focus modes swallow them. |
| **Notch** | The best of the four and still the same machine, the same lid, the same desk. |

The question the app exists to answer is *"can I start another long run?"*, and it gets asked away from the desk as often as at it: in a meeting, on a train, at 7am before opening the laptop. `QuotaAlerter` firing a critical-quota notification into a sleeping Mac is a notification nobody reads.

The obvious fix is an iPhone app, and it is enormous out of proportion to the payload. It means an App Store presence and review queue, an APNs push service to run, an account system to pair a Mac with a phone, a widget extension, a Live Activity extension, and a second release train alongside the Sparkle one. All of that to render one percentage.

Notify! has already built exactly that. It is a published app covering Mac, iOS and web push, whose entire premise is that a script somewhere else pushes content to a device you carry: it owns the push certificates, the device pairing, and on iOS the Live Activity and widget extensions that draw a Lock Screen and a Home Screen. What it exposes to the outside world is a plain HTTP gateway with no SDK and no bearer token, addressed by a device id and a per device secret the user copies out of the app.

So the whole feature on ClaudeBar's side is: turn the quotas it already holds into two small JSON bodies, and POST them to three routes.

## Behavior

Three surfaces, each switchable independently once the feature itself is on, and two of them carry the identical thing.

That last part is the premise rather than a coincidence, and it is what makes the third surface nearly free. The gateway derives the Home Screen widget's content contract from the same module its Live Activity uses: same fields, same caps, same merge rules, same validation messages, so any body that would start a Live Activity is already a valid Home Screen widget body. ClaudeBar builds the tile once, as one `NotifyTile` that `NotifyPayloadBuilder` hands to both surfaces, and `NotifyGatewayClient` encodes it through the same `tileBody` for both routes. Building it twice would only produce two things that were meant to be identical and one day were not, which on a phone reads as two different pictures of one quota.

**The metrics Live Activity** is the dense one. It carries the title `ClaudeBar`, a progress bar, a compact reset countdown where a timer would sit, and a row of up to six quota windows, each with its own label, value, unit and color. Six is the gateway's ceiling and also about the point at which a Lock Screen row stops being readable, so the two limits agree.

**The Home Screen widget** carries that same tile, and differs in when the user meets it. A Live Activity appears while something is happening and goes away when it stops; a Home Screen widget stays where it was placed and always shows the latest thing stored for it. So the tile answers "what is my quota right now" to somebody whose phone is already lit, and the Home Screen widget answers "what was my quota when I last looked", to somebody who went looking. Neither is a substitute for the other, which is why both are on by default and either can be switched off alone.

The Home Screen widget is also the newest surface on Notify!'s side, and that shows in two places. It needs a recent Notify!, where it is turned on under Settings then Home Screen Widgets. And creating one over the gateway puts nothing on a screen by itself: it fills a slot the user still has to place through iOS's own widget picker, the same as any other widget.

**The Lock Screen widget** is the glanceable one, and the only surface with a shape of its own. Its gauge is a single chosen quota: a headline value, a unit, a quieter second line naming the provider and the window, and a `progress` the gateway draws as a bar on the rectangular widget and as a ring on the circular one. The gauge shows whichever quota needs attention most until the user picks a specific one.

Four rules shape what all of that actually says, and all four live in `NotifyPayloadBuilder`:

- **Percentages are remaining, not used.** A 42% quota publishes `progress: 42`. Every other ClaudeBar surface reads that way, and a full ring meaning a full quota is the only intuitive mapping a gauge has.
- **The worst quota leads.** Readings sort by status severity, then by how little is left. The headline is the first one, and the tile takes its tint, its bar and its countdown from it.
- **Labels drop the provider name when they can.** A tile covering one provider reads `5h 7d`, not `Claude 5h Claude 7d`. The name comes back as soon as a second provider is on show.
- **Ordering is fully deterministic**, down to a name and quota-key tiebreak. Two payloads built from the same readings must compare equal, or the driver would republish forever.

Money based quotas have no percentage to draw. Their value is the formatted balance with no unit, and the tile's bar falls through to the worst quota that *does* have a percentage, rather than vanishing whenever a credit balance happens to be the headline.

### Publish cadence

Quota numbers move on every refresh and the reset countdown moves every minute, so "publish whenever the payload differs" is a request per refresh, forever. `NotifyPublishGate` adds four rules on top of the difference:

| Rule | Value | Why |
|---|---|---|
| Minimum gap, tile | 60 s | The tile is a push, so it can afford to be prompt. |
| Minimum gap, gauge | 15 min | iOS decides when a widget redraws, roughly every quarter hour. Pushing faster buys nothing. |
| Minimum gap, Home Screen tile | 15 min | Also a poll, on the same quarter hour and for the same reason. Nothing is ever pushed to it: the phone fetches the device's screen widget list when iOS decides to redraw the tile. |
| Keep alive, tile and Home Screen tile | 90 min | Two deadlines, both at **two hours**, both measured from the last write. The gateway ends a progress-only Live Activity that has gone that long without an update, on the grounds that a frozen percentage is worse than no tile; and a Home Screen widget's `staleAt` lands there too, after which the phone dims the tile rather than presenting old numbers as current. Ninety minutes clears both with room to spare. |

The gauge is the one surface with no keep alive. The gateway documents neither a reaper nor a freshness deadline for `/widgets`, so there is nothing a heartbeat there would prevent.

The keep alive is the reason `NotifyPublishDriver` runs a one minute timer at all. Both time based rules are unreachable from `@Observable` state alone: a change the gate suppressed for arriving too soon has to be offered again once its interval has passed, and nothing in observable state fires on the mere passage of time.

Saving credentials or pressing publish in the settings pane bypasses the gate entirely by clearing the record, because waiting a quarter of an hour to find out whether a token works is not an answer. The pane does that through `NotifyPublishDriver.publishNow()` rather than publishing for itself: the driver holds the stored handles and the single in-flight publish, and two publishers racing over one nil activity id is precisely how a phone ends up with two Live Activities.

### Recovery

Each failure mode below has a remedy of its own, and each one is a distinct case on `NotifyPublishError` for exactly that reason.

| What happened | HTTP | What ClaudeBar does |
|---|---|---|
| The user swiped the tile away | 410 | Forget the stored activity id and start a fresh tile, once. A retry loop here is a retry loop against the gateway. |
| A stored handle is refused | 403 | Forget that one handle, so the next publish creates a replacement for it. The gateway answers a missing token, a wrong token, an unknown id and somebody else's id identically, so a 403 is not evidence the credentials are bad: far more often the user deleted that one tile or widget in the Notify! app. The other surfaces' handles are left alone, because clearing one would abandon something alive and put a duplicate beside it. |
| Push to start backoff | 429 | Suppress tile writes until the gateway's own wait has passed. Every attempt inside the wait lengthens it. Both widgets keep publishing. |
| The phone has never opened Notify! | 409 | Report it and stop. No Live Activity can start until the device has a push-to-start credential, which only opening the app once produces. |
| Apple never answered a start | 502 `unknown` | Keep the activity id the gateway returned and update it on the next tick. Starting again could leave two tiles. |
| Apple refused a start | 502 `not-delivered` | Wait. No tile exists, so starting again is safe, but every unanswered start counts toward the same ladder as a 429, so the gateway's own `retryAfterSeconds` is honored and 30 minutes assumed when it names none. |
| Home Screen widgets are not being served | 503 | Pause that one surface for six hours and say so at info level, not as an error. This is the gateway's own kill switch rather than anything wrong here, and nothing on this Mac moves it, so asking again every minute would be a poll against a decision that has not changed. The other two surfaces are untouched. |

Some failures are not worth discovering over the wire. A Live Activity aimed at a `GRP`, `MC` or `WB` id is refused locally, before a request exists, because the outcome is already known: the gateway answers that start with a 400 saying the device cannot show one. Either widget aimed at a `GRP` id is refused for a different reason, that a group is not a device and owns no widget list to write into. What the user reads in both cases is the id's own reason, which names the kind of device they linked and tells them to use the device ID and token from their phone, rather than a status code that reads as ClaudeBar failing at something it should have managed.

The three surfaces are written independently, each addressed by its own stored handle and each failing for its own reasons. A tile the device refuses to start must not cost the user their widgets, which poll happily on a phone that cannot start a Live Activity at all, and a Home Screen route the gateway has not switched on yet must not silence the two surfaces it is already serving.

### Privacy

Every other network call ClaudeBar makes fetches a quota from the provider that owns it. This one is the first that sends ClaudeBar's own state outward, to a service that is neither the user's machine nor a provider they already have an account with, so it is worth being explicit.

- **What leaves the machine:** provider names, quota window labels, remaining percentages or credit balances, and reset countdowns. No prompts, no repository names, no file paths, no session content.
- **Where it goes:** `push.getnotifyapp.com`, a third party service, and from there to the user's own phone.
- **Off by default.** `NotifyConstants.defaultEnabled` is `false` and stays false until the user links a device. A feature that talks to someone else's server cannot ship enabled.
- **The token is a secret.** It goes to the Keychain-backed credential store under `CredentialKey.notifyDeviceToken` and never to `~/.claudebar/settings.json`. It is never logged, and neither is the device id above debug level, which never reaches the log file on disk.
- **When the Keychain refuses, the token falls back.** A locally built ClaudeBar is ad-hoc signed (`CODE_SIGN_IDENTITY` is `-`), so it has no stable identity for a Keychain item's access control to name and every call comes back `errSecAuthFailed` (-25293). A release build signed with a Developer ID is unaffected. `CredentialRepository.save` cannot report a refusal, so the save is read back and, when it did not stick, the token goes to the same UserDefaults credential store that already holds the GitHub, MiniMax, DeepSeek and Alibaba tokens. Still never `settings.json`. `notifyDeviceTokenIsSecure()` reports which store won, and the pane says so out loud rather than letting its "Configured" badge imply the stronger answer.

---

## Prior art

The gateway is the prior art, and it was read end to end from its own OpenAPI document (`https://getnotifyapp.com/apidocs/openapi.json`) before any of this was written.

Host `https://push.getnotifyapp.com`. `NotifyGatewayClient`'s initializer takes another only so tests can point it at a stub. These routes declare `security: []`: there is no bearer token, and the per device secret travels in `?token=`.

### The id namespaces, and which of them have a screen

The id half of those credentials is not one thing. Notify! mints several formats, in namespaces fenced against each other, and they are not interchangeable destinations.

| Id | What it names | Notification | Live Activity | Lock Screen widget | Home Screen widget |
|---|---|---|---|---|---|
| `GRP` + 5 | A notification group, which fans out to its members | yes | no | no | no |
| `MC` + 14 | A push capable Mac listener | yes | no | yes | yes |
| `WB` + 14 | A web push browser | yes | no | yes | yes |
| `IO` + 14 | An iPhone or iPad | yes | yes | yes | yes |
| 8 characters | The legacy app device format: an iPhone or iPad, or an older poll only Mac listener | yes | yes | yes | yes |
| anything else | A device format newer than this document | yes | yes | yes | yes |

**The three surfaces are gated differently.** A Live Activity is refused for a Mac and for a browser. Neither widget is, and both still refuse a group, because a group is not a device: it fans a notification out to its members and owns no surface of its own for anything to sit on. So the namespace decides two different things, and only the Live Activity rule turns on which device it is.

Note which way round the Live Activity rule is written. The namespaces that cannot show one are named and everything else is allowed, rather than the reverse, because app device ids are not one fixed shape: the legacy format is 8 characters, `IO` is 16, and more will follow. A list of what may pass would refuse a real phone on the day Notify! mints a format ClaudeBar has never heard of, and a refused phone reads as ClaudeBar being broken rather than as a new namespace.

ClaudeBar drives no notification route, so that column is not something it uses; it is there because it is what makes such an id a real id rather than a typo, and so a thing to explain rather than to refuse.

The Live Activity restriction is the gateway's own rule. It refuses a start with a **400** on the grounds that the target device cannot show Live Activities at all, naming a Mac of either generation and a web push browser. A group owns no Lock Screen to start anything on either.

Both widgets are the opposite, and identically so. The gateway is explicit that neither route carries a device type gate: legacy, `IO`, `WB` and `MC` ids can all own a Lock Screen widget, and it says the same of Home Screen widgets in so many words. Which of them actually draws one is Notify!'s business rather than a rule for ClaudeBar to invent. Only a group is refused, and only because a group is not a device: it has members, and no widget list of its own for a gauge or a tile to sit in. `NotifyDeviceKind.supportsScreenWidget` is therefore written as `supportsWidget` rather than as a second copy of the same switch, so the two can never drift into disagreeing about one id.

`NotifyDeviceKind` holds the whole rule and everything above it reads the same answer, through `liveActivityUnsupportedReason`, `widgetUnsupportedReason` and `screenWidgetUnsupportedReason` rather than one shared verdict. `NotifyGatewayClient` refuses a tile for a Mac, a browser or a group, and either widget only for a group, before a request exists. `NotifyPublishDriver` drops an unavailable surface from a decision rather than writing it once a minute forever. `NotifyPane` disables just the control that cannot work, with the sentence that explains that one, so a Mac user reads that their Live Activity is unavailable and that both their widgets are not.

One thing cannot be decided locally at all. The legacy 8 character format is shared by iPhones and by those older poll only Mac listeners, and nothing in the id separates them, so such an id is allowed through and the gateway has the last word: it answers the old Mac case with that same 400. An `IO` id carries no such ambiguity. A well formed id belonging to none of the namespaces above is allowed through for the same reason, so a format added after this was written still links; it differs from a known app device only in what the pane calls it, since claiming an unknown id is an iPhone would be a guess. Note too that `GRP` plus 5 is itself eight characters, so the two grammars genuinely overlap and the prefix is tested first, which is the gateway's own tie break: anything beginning with `GRP` goes to the group fan out and everything else is treated as a device.

### The fields are the type

**There is no tile type, and no widget display format.** No `activityType`, no `displayFormat`, nothing to select a layout with. Which fields are populated decides how the thing draws, and they compose. A title plus a progress bar plus a metrics row **is** the metrics tile. That is the single most surprising thing about this API, and it is what makes the feature cheap: ClaudeBar sends the six or seven fields it drives, says nothing at all about the rest, and gets the layout it wanted.

Saying nothing is load bearing in a second way, and it cuts both ways. Updates are JSON merge-patch: an absent field is left alone, a value replaces, an explicit `null` deletes. So `NotifyGatewayClient` deliberately never mentions `status`, `endsIn`, `steps`, `step` or `button`, and a ClaudeBar update can share a tile with whatever else the user configured.

The same rule makes silence dangerous for the fields ClaudeBar does drive. Omitting one it previously set does not clear it, it freezes it. A reset countdown would keep ticking beside a quota that no longer reports one, and a gauge would keep the last percentage after the shown reading became a credit balance with no percentage at all. Those two are not hypothetical: `trailing` is nil whenever the headline quota has no `resetsAt`, and `unit` and `progress` are both nil for a dollar based quota. So every field ClaudeBar owns is stated on every write, as an explicit `null` when it has no value. The widgets are where this matters most, since each lives under its `WG…` or `SW…` id until the user removes it, while a Live Activity is short lived and gets restarted anyway. `title` is the one exception: the gateway treats it as an identity and refuses to clear it.

`POST /live-activity/{id}?token=`

| Field | Type | Limit | Notes |
|---|---|---|---|
| `title` | string | 120 | Required to start. The tile's identity. |
| `body` | string | 300 | Second line, shown only when there are no metrics in its place. |
| `symbol` | string | 64 | SF Symbol name. |
| `tint` | string | hex | `#RRGGBB` or `#AARRGGBB`, leading `#` optional. |
| `progress` | number | 0 to 100 | The bar. Clamped, not rejected. `null` removes it. |
| `trailing` | string | 40 | Static text where a timer would go. |
| `metrics` | array | 6 items | JSON body only, no query spelling. Replaces wholesale. |

`metrics[]` is `{label (1 to 24, required), value (1 to 16 or a number, required), unit (8), color (hex)}`. An absent color inherits the tile tint.

`POST /widgets/{id}?token=`

| Field | Type | Limit | Notes |
|---|---|---|---|
| `title` | string | 120 | Required to create. The identity in the phone's widget picker. Can be replaced, never cleared. |
| `value` | string | 40 | Headline text, pre-formatted by the caller. Never math'd on device. |
| `unit` | string | 12 | Small label beside the value. |
| `detail` | string | 120 | Quieter second line. |
| `symbol` | string | 64 | SF Symbol name. |
| `tint` | string | hex | Accent color. |
| `progress` | number | 0 to 100 | The gauge: a bar on the rectangular widget, a ring on the circular one. |

`POST /screenwidgets/{id}?token=`

No third table, because there is nothing new to put in one. This route's content contract is derived from the Live Activity's, field for field, cap for cap and merge rule for merge rule, down to the wording of its 400s, so the tile table above describes it exactly and `NotifyGatewayClient` sends it through the same `tileBody`. What differs on the wire is the path and the id namespace: `SW` plus six characters, alongside `LA` and `WG`. A create addresses the device id, carries `"new": true` for the same never-hijack reason as the other two, and answers **201**; an update addresses the `SW…` handle and answers **200**. Both come back with the stored content, the handle, and `staleAt`.

Combined tile content must serialize under 2048 bytes, Lock Screen widget content under 1024, and Home Screen widget content under 2048: it inherits the tile's cap along with the tile's contract. `NotifyLimits` enforces every length above at construction, shortening rather than failing, because a quota label that happens to be long should shorten, never fail to reach the phone.

Two statuses mean something on `/screenwidgets` that they mean nowhere else in this client, so `publishScreenTile` translates them where that difference is known rather than inside the shared mapping every other route would then have to reason about.

- **503** is the server side kill switch, and no other route has one. Home Screen widgets ship behind it, so creates and updates can be refused while reads and deletes stay deliberately open and an already placed tile keeps rendering. It means the feature is not being served yet, not that anything is wrong with ClaudeBar, the credentials or the content, so it becomes `surfaceSwitchedOff`, which is retryable and whose sentence says ClaudeBar will try again later.
- **409** here means the device dialect found several screen widgets and cannot say which was meant. The shared mapping reads a 409 as `liveActivityUnavailable`, because that is what it means on the route it was written for, and sending somebody to open the Notify! app about their Live Activities would be a wrong answer to a question about a Home Screen widget. ClaudeBar creates its own with `new` and addresses it by `SW…` id afterwards, so it should never meet this at all.

### Two dialects, and why ClaudeBar only uses one of them

All three write routes take either a **device id** or a **handle**, and the handler decides by looking the id up rather than by its shape. That last part is not pedantry: a legacy device id is eight arbitrary alphanumerics, so one can perfectly well begin with `SW`, and a gateway that read the prefix would send that device's write to somebody's widget.

- Device id, the *upsert* dialect: the first call starts the device's single live tile and later calls update it in place.
- `LA######` / `WG######` / `SW######`, the *precise* dialect: always that exact tile or widget.

The upsert dialect is the shorter code and it is wrong here. A user who has a Notify! tile running from some other script of their own would find ClaudeBar had taken it over, silently, with a quota. So ClaudeBar always creates its own: the first write carries `"new": true` against the device id, the returned `LA…`, `WG…` or `SW…` handle is persisted to `notify.activityId` / `notify.widgetId` / `notify.screenWidgetId`, and every write after that addresses the handle. `new` never appears on an update, where it would leave the device with two tiles.

`new=1` earns its keep twice over: it is also the gateway's documented override for the sticky-dismissal 410, which is what lets a tile the user swiped away be replaced.

### The reapers, and the freshness deadline

Three server side rules end a Live Activity without being asked, and only the first one matters to a quota display:

- a progress-only tile with no update for **2 hours** is ended as `abandoned`
- a countdown that passes its finish by 30 minutes with no end call is ended as `overdue`
- a tile still live 9 hours after starting is `expired` (Apple's own ceiling is 8)

A Home Screen widget is never ended, because there is nothing there to end: `end` and `keepFor` are accepted on that route and silently ignored rather than refused. What it has instead is `staleAt`, epoch seconds returned with every write and computed from that write, never from a read. It falls **two hours** after the write, or five minutes past a countdown's promised finish when the body carried one, which ClaudeBar's never does. Past it the phone dims the tile and says how long ago it was current rather than presenting old numbers as live. That is the honest failure for a surface that stays put: a publisher that stops writing leaves a tile that visibly stops being current instead of one that lies. So a Home Screen tile has to be rewritten inside two hours.

Two deadlines, both two hours, both measured from the last write, and one heartbeat clears both. That is the entire reason `NotifyPublishGate` has a keep alive, and the reason the Home Screen tile takes it as well as its own fifteen minute interval while the gauge takes only its interval.

### The one call that is rate limited

`GET /link?id=&token=` validates a pair and describes the device it names, and the gateway allows **five calls a minute per IP**. It belongs behind an explicit "Verify Device" button and nothing else. Nothing on a timer may call it. It also has an error envelope of its own and answers **404**, not the 403 every other route uses, for a pair it does not recognise, giving that same 404 for a wrong token and for an id that does not exist so it cannot be used to enumerate ids. `NotifyGatewayClient` translates it to rejected credentials, because to the person who has just pasted their link it is the same problem. It also answers for groups, and a group carries none of the three surfaces, so `NotifyGatewayClient` rejects `type: "group"` there rather than letting it fail later with a puzzling 400.

### In-repo precedent

`NotifyPublishDriver` is `NotchWindowDriver` with the surface swapped. Both drive something SwiftUI does not own from `@Observable` domain state, and both do it with `ObservationRenderSync`: one sync watches the setting that turns the feature on, a second reads every property the output depends on and pushes only distinct values. The notch's output is an `NSPanel`. Notify!'s output is a phone.

---

## Architecture

Notify! is a **destination**, not a provider. `QuotaMonitor` remains the single source of truth per `AGENTS.md`, and nothing in this feature reads a quota from anywhere: it reads the ones already in memory. See [docs/architecture/ARCHITECTURE.md](../../architecture/ARCHITECTURE.md) for the layering this sits inside.

Domain holds every decision as pure value types: the device link and its kind, the field limits, the tile and gauge content, the payload builder, the publish gate and the error cases, plus the `@Mockable` `NotifyPublishing` port. Infrastructure has one implementation, `NotifyGatewayClient`. The App layer owns `NotifyPublishDriver`, `QuotaMonitor+NotifyReadings` and `NotifyPane`.

The dependency direction is the usual one. Domain declares `NotifyPublishing` and knows nothing about URLs; `NotifyGatewayClient` in Infrastructure is the implementation and the only place `URLRequest` appears; the App layer owns the driver, because that is where `QuotaMonitor` and `AppSettings` both are.

`QuotaMonitor+NotifyReadings.swift` is the seam worth naming. `AIProvider` is main actor isolated and `NotifyPayloadBuilder` takes `Sendable` values, so something has to flatten one into the other, and it has to happen inside the driver's observation read closure. It reads `enabledProviders`, each provider's `snapshot`, and the quotas hanging off it, unconditionally and without caching or filtering, because a property this function skips is a property observation never registers, and a quota that changed afterwards would never reach the phone.

Settings keys, all under `notify.*` in `~/.claudebar/settings.json`:

| Key | Holds |
|---|---|
| `notify.enabled` | Whether ClaudeBar publishes at all. Default `false`. |
| `notify.deviceId` | The linked device id. |
| `notify.liveActivityEnabled` | Whether the tile is published. Default `true`. |
| `notify.widgetEnabled` | Whether the gauge is published. Default `true`. |
| `notify.screenWidgetEnabled` | Whether the Home Screen tile is published. Default `true`, because a 503 is handled as "not yet" rather than as an error, and shipping it off would mean nobody saw the surface on the day Notify! switched it on. |
| `notify.gauge.providerId`, `notify.gauge.quotaKey` | Which quota the gauge shows. Both empty means automatic. |
| `notify.activityId`, `notify.widgetId`, `notify.screenWidgetId` | The handles of the Live Activity, the Lock Screen widget and the Home Screen widget ClaudeBar created. |

The device token is the exception and never appears here. It goes to the secure credential store under `CredentialKey.notifyDeviceToken`.

### The testable core

Everything that decides anything is a pure value type in Domain, with no clock, no network and no settings lookups of its own. `NotifyPayloadBuilder` takes readings and a selection and returns a payload; `NotifyPublishGate` takes a payload, the last record and a `now` and returns one boolean per surface; `NotifyDeviceLink` and `NotifyLimits` are parsers. `NotifyGatewayClient.failure(status:data:retryAfterHeader:)` is static and takes the raw body, so every status code can be driven through it without a network stub.

`NotifyPublishDriver` is deliberately free of judgement. It was written when there was no App test target, so anything decided there would have gone untested; `Tests/AppTests` exists now, but keeping the driver to I/O still keeps the rules in the pure Domain types where they're cheapest to test. It gathers state, asks the builder and the gate, and performs the I/O the answer implies.

The Domain tests (`Tests/DomainTests/Notify/`) and `NotifyGatewayClient` tests pin every rule in this document, including each status-code mapping above.

---

## Delivery

**Phase 1, the pipe.** `NotifyDeviceLink`, `NotifyGatewayClient`, and the settings pane's link and verify path. Proves the credentials, the two dialects and the handle round trip against a real phone. This is the part that cannot be desk-checked.

**Phase 2, the content.** `NotifyPayloadBuilder`, `NotifyTile`, `NotifyGauge`, `NotifyLimits`. All pure, all TDD, no device needed once phase 1 has confirmed what the gateway accepts.

**Phase 3, the cadence.** `NotifyPublishGate` and `NotifyPublishDriver`: dedupe, minimum intervals, keep alive, and every recovery path in the table above. This is where the feature stops being a demo and starts being something that can be left on for a week.

Ships behind `notify.enabled`, default off, in Settings under its own Notify! pane. The pane is where the device is linked, any of the three surfaces is switched off, the gauge's quota is chosen, and a publish can be forced. It posts `.notifySettingsChanged` on save, because credentials and the surface handles live outside observable state and the driver has no other way to notice them.

## Considered and rejected

**Send `endsIn` for a live countdown to the reset.** The gateway will happily tick a countdown locally on the device, which sounds strictly better than the static `trailing` text ClaudeBar sends. It was cut because the countdown claims the tile's progress rendering, and the quota needs that bar: a tile cannot show both how much is left and how long until it refills, and the percentage is the thing the app exists for. Two smaller reasons agree. A countdown 30 minutes past its finish is reaped as `overdue`, so every window roll would need an end call and a fresh start, and a fresh start is the one operation subject to push-to-start backoff.

**Use the device scoped upsert URL instead of storing handles.** `POST /live-activity/{deviceId}` is one line shorter and needs nothing persisted. It also takes over whichever tile the device last had, which for a Notify! user is very likely one of their own scripts. The cost of doing it properly is two strings in `settings.json` and a `new=1` on the first write. That is a trivial price for never silently replacing something the user built.

**Publish from `QuotaMonitor.handleSnapshotUpdate`.** The snapshot hook already exists, already fires on fresh data, and is where `QuotaAlerter` is called from, so it looks like the natural home. It is wrong three ways. It runs once per provider, so a refresh across five providers would publish the same combined state five times. It is in Domain, which cannot see `AppSettings` or Infrastructure, so it could not read the switches or the gauge selection that shape the payload. And it would bypass `ObservationRenderSync` entirely, losing the dedupe that is the whole reason an unchanged quota costs no HTTP at all. An `ObservationRenderSync` fires once per distinct *state*, which is exactly the unit a publish should be measured in.

## Open questions

- **More than one gauge.** The gateway allows 10 widgets per device, so a widget per provider is possible. Unresolved: the widget title is its identity in the phone's picker, so several widgets need distinguishable titles that are still recognizably ClaudeBar, and it is not obvious whether four rings is more useful than one ring plus the metrics tile already beside it.
- **Should an exhausted window end the tile?** `endTile(link:activityId:keepFor:)` is implemented and the driver never calls it. `keepFor` would leave the final state readable on the Lock Screen for up to four hours. Proposal: no. A depleted quota is precisely when the number matters most, and a tile that vanishes at 0% is a tile that disappeared exactly when the user went looking for it.
- **Notify! groups.** `GET /link` already reports `type: "device"` or `"group"`, and the client rejects a group because a group cannot carry a Live Activity or a widget. Publishing to a phone and an iPad at once therefore means a list of device links rather than one, with per device handles and per device backoff state. Worth doing only once somebody asks for it.
