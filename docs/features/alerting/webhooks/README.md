---
description: Send ClaudeBar's quota alerts and status alerts to a Slack channel or a URL you own, as a Slack message or a JSON body. Use when wiring quota into Slack, a script or a service, or when a webhook says Failed.
---

# Webhooks

[Quota alerts](../quota-alerts/README.md) and the [status alerts](../status-alerts/README.md) tell *you*, on this Mac. A webhook sends the same alerts somewhere else: a Slack channel your team watches, a script on a home server, a monitoring service. It can also send the [weekly recap](../recap-alerts/README.md) — the week across every provider, once a week.

A webhook has no percent of its own. It sends the percents you already chose under Quota alerts and, if you tick it, every status that got worse (low, critical, empty) and the week that closed.

## Set up

**Settings → Sync & Alerts → Webhooks → Add Webhook**:

1. Paste the **URL**. It must be `https://`, except for a host on this Mac or your network (`localhost`, `192.168.…`, `*.local`).
2. Pick the **channel**: **Slack** for a Slack incoming webhook, **JSON** for anything else.
3. Pick **For**: **Every login**, or one provider.
4. Tick what it **sends**: **Quota alerts**, **Status alerts**, the **Weekly recap**, or any mix. The recap sends the week that closed each time your calendar's week turns — see [recap webhooks](../recap-alerts/README.md).
5. Press **Add**, then **Send a test**.

Each webhook shows its name (the URL's host until you type one), its channel and scope, an on/off switch, and its last delivery: *Sent 2m ago*, *Failed — 404*, or *Nothing sent yet*.

**Edit** changes the name, channel, scope and what it sends. The URL is never shown again: leave the field empty to keep it, or paste a new one to replace it. **Remove** deletes the webhook and its URL. Turning a webhook off keeps it, its URL and its last delivery.

## What it sends

**Slack** gets one line, the words of the Mac's notification:

```json
{ "text": "Claude · work is below 35% — 34% left" }
```

**JSON** gets every field on every send, `null` where there is no value:

```json
{ "type": "quota", "provider": "claude", "login": "Claude · work",
  "below": 35, "left": 34, "status": null, "was": null,
  "sentAt": "2026-10-22T09:41:00Z" }
```

`type` is `quota`, `status` or `test`. A status alert fills `status` and `was` (`warning`, `critical`, `depleted`) instead of `below` and `left`. A webhook that also sends the **Weekly recap** gets a fourth message, `"type": "recap"`, with the week's total, change, split by provider, top model, biggest day and cache savings — [recap webhooks](../recap-alerts/README.md) has the fields and the timing.

**Send a test** sends a message that says it is a test (`"type": "test"`), never a made-up alert.

## Privacy

The URL is a **secret**: a Slack URL carries a token. It is kept in the Keychain, never in `settings.json` and never in a log. On a build the Keychain refuses (one you compiled yourself), it is kept in the app credential store instead and the card says so → [settings.md](../../../settings.md#where-secrets-live).

What leaves your Mac: the provider, the login's name as the menu shows it, the percent and the status. No email, prompt, path or session.

## Gotchas

- **Failed — 404 / 403**: the URL is wrong or was revoked. Slack revokes a webhook when its app is removed.
- **One attempt, no retry.** A URL that is down misses that alert; the next alert is sent as usual.
- **Told again after a restart**: a login still below your percent is told once more after a relaunch, as on the Mac.
- A **paused** login is never refreshed, so it is never sent.

## See also

[design.md](design.md) · [Quota alerts](../quota-alerts/README.md) · [Status alerts](../status-alerts/README.md) · [Recap webhooks](../recap-alerts/README.md) · [settings.md](../../../settings.md)
