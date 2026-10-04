---
description: Track Alibaba Coding Plan (Model Studio / Bailian) 5-hour, weekly and monthly quotas with an API key or console cookies. Use when setting up Alibaba or when it shows "Session expired".
---

# Alibaba

Shows your Alibaba Coding Plan quota: the 5-hour session window, the weekly window and the monthly window, each as "used / total" with its reset time. The plan name appears as the account label.

## Setup

1. Subscribe to the Coding Plan in the Alibaba Cloud console for your region.
2. Settings → Providers → Alibaba → turn it on. It is off by default.
3. Pick the **Region**: International (Model Studio, `modelstudio.console.alibabacloud.com`) or China Mainland (Bailian, `bailian.console.aliyun.com`). The default is International.
4. Paste an **API Key**, or leave it empty to use your console session (below).

**Open Dashboard** opens the Coding Plan page for the selected region.

## Data sources

| Data source | Needs | Pick it when |
|---|---|---|
| API Key (default) | A Model Studio key in **API Key** | You have one. With no key saved, it hands over to the console session |
| Console Cookie | A browser signed in to the Alibaba Cloud console, or a cookie header pasted into **Console Cookie** | You don't use an API key |

The console session uses a pasted **Console Cookie** first, then the browser's.

## More than one account

**Accounts → Add Account** asks for what the active data source needs: an API key and region, or a console cookie and region. An added account never reads the browser.

## Permissions

- **The browser's console session** reads browser cookie stores. Safari's store needs **Full Disk Access** for ClaudeBar; Chromium browsers (Chrome, Edge, Brave, Arc…) make macOS ask for access to the browser's "Safe Storage" Keychain item. An API key or a pasted cookie needs neither.

## Gotchas

- **"Session expired. Re-authenticate in Alibaba Cloud console."** ([#149](https://github.com/tddworks/ClaudeBar/issues/149), still open). The console answered with a "log in" response, or ClaudeBar couldn't find a `sec_token` for the session. What to try, in order:
  1. Check that **Region** matches the console you signed in to.
  2. Sign in to the console again in your browser.
  3. Paste a fresh cookie header, copied from a console request in the Network tab, into **Console Cookie**.
- **The browser used is the first that has any Alibaba cookie**, in the order Safari, Chrome, Edge, Brave, Arc and so on. A browser where you were signed in long ago can win over the one you use now. If so, paste the cookie.
- **A rejected API key falls back to the console session.** If neither works, the API key's failure is the one shown.
- The maintainers have no Coding Plan account (it was out of stock when they tried), so this provider was built from the console's request format and has not been confirmed against a live account. Logs from a working or failing account help: see [design.md](design.md).
- The API key and pasted cookie live in the Keychain, moved there from the app's preferences the first time they're read.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
