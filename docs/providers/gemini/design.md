# Gemini: design

Contributor notes for the Gemini provider. For setup, see the [README](README.md).

## As data

Gemini is `Modules/Providers/Resources/Providers/gemini.json` and `gemini-quota.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names it. Ported from #395.

- **`http.steps`.** `project` (`loadCodeAssist`) is `optional` with `attempts: 3` and keeps `$.cloudaicompanionProject`; `quota` sends `{"project": …}`, or `{}` when no project was found (`dropEmpty`). A 401 on either step is the whole data source's: it renews the login.
- **The login is renewed by its CLI** (`refresh: {"cli": …}`): on a 401, `gemini` runs with `/quit`, renews `oauth_creds.json` itself, and the file is read again. The refresher tells the data source it doesn't write back (`writesBack`), so ClaudeBar never writes Google's file. Never proactive: the expiry isn't checked, as before.
- **Window law.** The response states a reset time but no window, so no window is given; the probe used 7 days.
- **Accounts.** An added account is a signed-in `GEMINI_CLI_HOME`; its login file and its CLI renewal use that folder, and it waits for one refresh by hand before the background (`verifyBeforeBackground`).
- **Not taken:** the `/stats` CLI source the old code could parse; it was off as unreliable and stays off.

## Sources

| Step | Call | Notes |
|---|---|---|
| Credentials | `~/.gemini/oauth_creds.json` → `access_token` | Written by gemini-cli's "Login with Google". `isAvailable()` only checks that this file exists |
| Project | `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` → `cloudaicompanionProject` | Body `{"metadata":{"pluginType":"GEMINI"}}`, the same bootstrap call gemini-cli makes. Up to 3 attempts, 400 ms and then 600 ms apart, to ride out cold-start network delays. The "200ms, 500ms, 1000ms" in the code comment is stale. A 401/403 isn't retried |
| Quota | `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` with the project ID | Returns `buckets[]`: `modelId`, `remainingFraction`, `resetTime` (ISO 8601) |
| Token refresh | Run `gemini` with `/quit` as input (15 s timeout), wait 1.5 s, retry once | Only after an `authenticationRequired`. The CLI refreshes the token when it starts. ClaudeBar doesn't do an OAuth refresh itself |

`GeminiUsageProbe` goes straight to the API probe. `GeminiCLIProbe` (runs `gemini` with `/stats` and parses the model usage table) is still in the source, but the call to it has been commented out as "not working reliably". Its parser remains for tests.

## Why `loadCodeAssist` (#124, #122)

Project discovery used to call `cloudresourcemanager.googleapis.com/v1/projects`. A personal Google sign-in has no GCP scope, so that call failed. `retrieveUserQuota` then went out without a project and came back with three dummy "100% remaining" buckets. It also hid `gemini-3-*-preview` for users eligible for that tier. An earlier workaround ("use any GCP project") helped only users who have a GCP project. `loadCodeAssist` returns the project gemini-cli itself uses, so it works for everyone. If discovery still fails, the quota call goes out without a project and the log warns that the numbers may not be accurate.

## Mapping buckets

1. Keep the lowest `remainingFraction` for each `modelId`.
2. **Merge aliases that share a tier.** Code Assist sets quota by tier (Pro / Flash / Flash-Lite) but reports the same bucket under every model ID the user may call. Calling `gemini-3-pro-preview` reduces `gemini-2.5-pro` and `gemini-3.1-pro-preview` by the same amount. Entries are grouped by (tier, fraction, resetTime). The stable, non-preview ID survives, then the highest version, then alphabetical order. The row is labelled with the bare tier name ("Pro", "Flash", "Flash Lite") to match gemini-cli's `/model` view. Check for Flash-Lite before Flash, because "flash" is a substring of both. Models without a recognisable tier keep their raw ID.
3. Sort by remaining fraction, lowest first, with the model ID breaking ties. This puts the model under pressure at the top instead of under models at 100%, and keeps the order from shuffling between refreshes.
4. `resetTime` is parsed with and without fractional seconds. It used to be shown as a raw ISO string.

## Known limits

- The quota type is `.modelSpecific(<tier label>)`, so a saved menu-bar selection is tied to that label. Renaming a label (e.g. "Flash Lite") breaks existing selections.
- If `oauth_creds.json` has expired and `gemini` isn't installed, there's no way to refresh it. The user sees "Authentication required".
