# Alibaba: probe design

Research notes for the Alibaba Coding Plan probe. Written 2026-09 from the code, commit history (2026-03-12) and [#149](https://github.com/tddworks/ClaudeBar/issues/149).

## Status: unverified against a live account

The provider was written on 2026-03-12 in response to #149, before the maintainers could get an account (the plan was out of stock in both regions on 2026-03-15 and again on 2026-03-30). The request shapes come from how the console calls its own gateway. The only field report so far is from the #149 reporter, and it failed:

```
[ERROR] [credentials] Alibaba connection test failed: Session expired. Re-authenticate in Alibaba Cloud console.
```

Re-login in Auto mode, a fresh Manual cookie and an API key all failed for that reporter. The reporter says CodexBar supports the plan correctly (2026-03-29), so CodexBar's implementation is the best lead for whoever picks this up.

## Sources

Both modes call the same console action, `zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2`, with a region-specific `commodityCode`.

| Region | Console host (API key mode, dashboard) | Console RPC host (cookie mode) | RPC action | `commodityCode` | Region id |
|---|---|---|---|---|---|
| International | `modelstudio.console.alibabacloud.com` | `bailian-singapore-cs.alibabacloud.com` | `IntlBroadScopeAspnGateway` | `sfm_codingplan_public_intl` | `ap-southeast-1` |
| China Mainland | `bailian.console.aliyun.com` | `bailian-beijing-cs.aliyuncs.com` | `BroadScopeAspnGateway` | `sfm_codingplan_public_cn` | `cn-beijing` |

### API key mode

`POST https://<console host>/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2&product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2&currentRegionId=<region id>`

- JSON body `{"queryCodingPlanInstanceInfoRequest": {"commodityCode": …}}`.
- The key goes in both `Authorization: Bearer <key>` and `X-DashScope-API-Key`.
- HTTP 401/403 → "Authentication required".

This is a **console** endpoint, not a DashScope API endpoint. If the console ignores the key and answers "need login", the parser reports "Session expired". That would explain why the API key also failed in #149, and it's the first thing to check with a real account.

### Cookie mode

`POST https://<console RPC host>/data/api.json?action=<RPC action>&product=sfm_bailian&api=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2`

- Form body: `params` (a JSON string `{"Api": …, "V": "1.0", "Data": {"queryCodingPlanInstanceInfoRequest": {"commodityCode": …, "onlyLatestOne": true}}}`), `region`, `sec_token`.
- Headers: `Cookie`, `X-Requested-With: XMLHttpRequest`, and `x-csrf-token` taken from the `login_aliyunid_csrf` cookie when present.
- `sec_token` comes from the cookie of that name. Otherwise the probe GETs the region's dashboard page with the cookie and pulls it out of the HTML (`"sec_token":"…"` or `sec_token = '…'`). If neither works → "Session expired".
- HTTP 401/403 → "Session expired".

### Browser cookie extraction (Auto)

SweetCookieKit, browsers in its default order (Safari, Chrome, Edge, Brave, Arc, Dia, ChatGPT Atlas, Chromium, Helium, Vivaldi, Firefox, Zen, then beta/canary builds). Domains `aliyun.com` and `alibabacloud.com` by suffix, expired cookies excluded. Only these names are kept: `login_aliyunid_ticket`, `login_aliyunid_csrf`, `sec_token`, `aliyun_choice`, `cna`. The **first store with any of them wins**.

Known weakness: `cna` is a tracking cookie that exists without a login, so a signed-out browser can win, send no ticket and get "Session expired". The region is also ignored at this step, so `aliyun.com` (China) and `alibabacloud.com` (International) cookies can be mixed together.

## Response parsing

The payload is wrapped in varying envelopes, so the parser is deliberately loose:

1. Any `code`/`status` string containing `login` (e.g. `NeedLogin`), or `message`/`msg` containing `log in`/`login` → "Session expired". A `statusCode` of 401/403 anywhere → "Authentication required".
2. `data`, `DataV2`, `successResponse` and `success_response` wrappers are flattened recursively.
3. From `codingPlanInstanceInfos`, the first entry with `status`/`instanceStatus` `VALID` or `ACTIVE` is used, else the first entry.
4. Its `codingPlanQuotaInfo` is used, or failing that any dictionary with `per5HourUsedQuota`/`perWeekUsedQuota`-style keys.

| Window | Used / total fields | Reset field |
|---|---|---|
| 5-hour (session) | `per5HourUsedQuota` / `per5HourTotalQuota` (also `perFiveHour…`) | `per5HourQuotaNextRefreshTime` |
| Weekly | `perWeekUsedQuota` / `perWeekTotalQuota` | `perWeekQuotaNextRefreshTime` |
| Monthly | `perBillMonthUsedQuota` / `perBillMonthTotalQuota` (also `perMonth…`) | `perBillMonthQuotaNextRefreshTime` |

Reset times are accepted as ISO 8601 with offset (`2026-03-12T19:17:15+08:00`), with or without fractional seconds, or as epoch seconds (number or string). Plan name comes from `planName`, `instanceName` or `packageName`. A window with total 0 is skipped; no windows at all → "No quota windows found in payload".
