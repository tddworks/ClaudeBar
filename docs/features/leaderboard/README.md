---
description: Join the ClaudeBar Leaderboard with a username, share daily token totals from Claude, Codex or Mistral, and see your rank. Use when joining, changing what you share, or leaving.
---

# Leaderboard

Rank your AI coding token usage against other ClaudeBar users. You join with a username, choose which providers to share, and ClaudeBar uploads your daily token totals every hour. It's off until you join.

Contributors: [design.md](design.md).

## What's shared

Only this, for each provider you tick and each day:

- your **username**
- **input**, **output**, **cache-write** and **cache-read** token counts (a log that keeps only a total is shared as that total)
- your Mac's **date**, so your "Today" is your own day
- only if you turn on **Show my country on the globe**: your **country**, which the server takes from where your requests come from. Your Mac sends no location. Never your city or IP

Never prompts, file names, projects, costs, model names or your account email. Every upload is signed by a key made on your Mac when you join; the private half never leaves it.

## Which providers

Providers whose logs ClaudeBar reads for daily usage can be shared:

| Provider | Read from |
|---|---|
| Claude | `~/.claude/projects` (or each added account's folder) |
| Codex | `~/.codex/sessions` (or each added account's `CODEX_HOME`) |
| Mistral | `~/.vibe/logs` |

Quota-only providers (Gemini, Copilot, Cursor and the rest) report percentages, not tokens, so they can't be ranked. If you have several accounts for one provider, their tokens are added together.

## Joining

1. Open the ClaudeBar menu and pick the **Leaderboard** pill after your providers.
2. Type a username: 3–20 letters, numbers, `-` or `_`. It's shown publicly.
3. Tick the providers to share, and open **Exactly what gets uploaded** if you want to check.
4. Press **Join leaderboard**. Your last 30 days are uploaded straight away.

The tab then shows your rank (the eye next to your name shows it as `@i•••` for screen shares) and your provider mix, the board (up to the top 100, scrolling inside its card; while your own row is scrolled out of sight, a copy of it sits under the list and takes you there), and when the last upload went. Switch between **Today**, **7 days** and **30 days**, or one provider. **Full board** opens the public page at [claudebar.tddworks.com/leaderboard](https://claudebar.tddworks.com/leaderboard).

## Settings → Leaderboard

| Setting | Does |
|---|---|
| **Username → Rename** | Takes a new name if it's free |
| **Show me on the web board** | Off keeps you ranked only in your own ClaudeBar |
| **Profile link** | One handle on X, Instagram or GitHub, shown as an icon after your name on the board. Not verified. **Remove** takes it off |
| **Show my country on the globe** | Puts your country on the web board's globe. Its tokens show once three members there opt in. Off forgets it at once |
| **Shared providers** | Stops or starts uploads per provider. Days already uploaded stay until you leave |
| **Export my data** | Saves everything the server holds about you as JSON |
| **Leave and delete my data** | Deletes your username and every uploaded day from the server, then this Mac's key |

## Profile link

Add one place people on the board can find you: an **X**, **Instagram** or **GitHub** handle, when you join or in **Settings → Leaderboard → Profile link**. It shows as that platform's icon after your name, in the app and on the web board; clicking it opens the profile. You type only the handle; the link is always built from the platform's own address. Links aren't verified, and the board says so.

## The globe

The web board's globe shows where ClaudeBar is used, by country, from members who opted in. Turn it on when you join, from the **New** card in the Leaderboard tab, or in **Settings → Leaderboard**. The tab's **🌍 Members in N countries** line opens it. Once you're on it, that line names your country; the **eye** next to it shows it as `🌍 ••` for screen shares, like the eye that masks account emails, and **Turn off** takes you off the globe.

## Gotchas

- **On a VPN?** Your country is taken once, when you turn the globe on, so a VPN's country then is the one kept. To change it, turn **Show my country on the globe** off and on again without the VPN.

- **"That username is taken."** Names are unique ignoring case, and names that would read as official (`admin`, `claudebar`, `anthropic`…) are reserved.
- **"This Mac's clock is more than five minutes off."** Uploads are signed with the time. Fix the clock in System Settings → General → Date & Time.
- **Reinstalled, or your Keychain was reset?** The key is gone, and with it the way to prove the name is yours. Join again with a new name; ask on GitHub to have the old one removed.
- **A locally built ClaudeBar** can't use the Keychain, so the key is kept in the app's preferences instead, as Notify!'s token is.
- **The board ranks by total tokens**, cache reads included, so cache-heavy Claude use counts a lot. Totals are self-reported; nothing rides on them.
