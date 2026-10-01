---
description: Track Alibaba Coding Plan (Model Studio / Bailian) 5-hour, weekly and monthly quotas with an API key or console cookies. Use when setting up Alibaba or when it shows "Session expired".
---

# Alibaba

Shows your Alibaba Coding Plan quota: the 5-hour session window, the weekly window and the monthly window, each as "used / total" with its reset time. The plan name appears as the account label.

## Setup

1. Subscribe to the Coding Plan in the Alibaba Cloud console for your region.
2. Settings → Providers → Alibaba → turn it on. It is off by default.
3. In **Alibaba Configuration**, pick the **REGION**: International (Model Studio, `modelstudio.console.alibabacloud.com`) or China Mainland (Bailian, `bailian.console.aliyun.com`). The default is International.
4. Pick an auth mode (below), then press **Save & Test Connection**. The result line shows "Success: Connection verified" or the error.

**Open Alibaba Cloud Console** opens the Coding Plan page for the selected region.

## Auth modes

| Mode | Needs | Pick it when |
|---|---|---|
| API key | A key pasted into **API KEY** | You have one. If a key is saved, it is always used and the cookie settings are ignored |
| Cookie, Auto (from browser) | A browser signed in to the Alibaba Cloud console | You don't want to handle secrets by hand |
| Cookie, Manual | The cookie header from your browser's developer tools, pasted into **COOKIE STRING** | Auto picks up the wrong browser or nothing at all |

The cookie modes are picked under **COOKIE SOURCE**. To go from the API key back to cookies, press **Remove API Key**.

## Permissions

- **Auto (from browser)** reads browser cookie stores. Safari's store needs **Full Disk Access** for ClaudeBar; Chromium browsers (Chrome, Edge, Brave, Arc…) make macOS ask for access to the browser's "Safe Storage" Keychain item. API key and Manual modes need neither.

## Gotchas

- **"Session expired. Re-authenticate in Alibaba Cloud console."** ([#149](https://github.com/tddworks/ClaudeBar/issues/149), still open). The console answered with a "log in" response, or ClaudeBar couldn't find a `sec_token` for the session. What to try, in order:
  1. Check that **REGION** matches the console you signed in to.
  2. Sign in to the console again in your browser, then **Save & Test Connection**.
  3. Switch **COOKIE SOURCE** to **Manual** and paste a fresh cookie header copied from a console request in the Network tab.
- **Auto uses the first browser that has any Alibaba cookie**, in the order Safari, Chrome, Edge, Brave, Arc and so on. A browser where you were signed in long ago can win over the one you use now. If so, use **Manual**.
- **The API key replaces the cookie completely.** A saved key that the endpoint rejects shows "Authentication required", and the cookie is not tried as a fallback.
- The maintainers have no Coding Plan account (it was out of stock when they tried), so this provider was built from the console's request format and has not been confirmed against a live account. Logs from a working or failing account help: see [design.md](design.md).
- The API key and the manual cookie are stored in the app's UserDefaults credential store, not in `settings.json`.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
