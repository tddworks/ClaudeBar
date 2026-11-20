# Copilot — design

What the Copilot card shows is AI credits for the month: the quota is *Monthly* (`.timeLimit("Monthly")`), it resets on the 1st at 00:00 UTC, and every user-facing string says "AI credits", while storage keys and API URLs keep their old names.

## As data

Copilot is `Modules/Providers/Resources/Providers/copilot.json` with `copilot-billing.js` and `copilot-user.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it. Ported from #391; the old probes' plan is in the git history of this file.

- **Two data sources**, `billing` and `copilotAPI`, the old Probe Mode's values, so `copilot.probeMode` is read as it was.
- **The username travels with the key.** Billing's credential adds `username` from its setting (`with`) and refuses a blank or malformed one (`match`, checked after `with`), so Billing without a username is not ready rather than a bad URL.
- **The plan carries the allowance, the report and the unit.** GitHub's billing report has no allowance, so Billing asks for **Copilot Plan**, an account-scope choice whose options carry `allowance`, `report` and `unit` (GitHub's published allowances, read 2026-10-31 from [usage-based billing for individuals](https://docs.github.com/en/copilot/concepts/billing-and-usage/individuals/billing) and [plans](https://docs.github.com/en/copilot/get-started/plans): Pro 1,500, Pro+ 7,000, Max 20,000, Business 1,900 and Enterprise 3,900 AI credits per user). The URL is `/users/{{username}}/settings/billing/{{setting.plan.report}}/usage`: `ai_credit` for every plan on usage-based billing (live since 2026-06-01), `premium_request` only for the two *annual on premium requests* options. Those are the Pro and Pro+ annual subscribers GitHub left on [request-based billing](https://docs.github.com/en/copilot/reference/copilot-billing/request-based-billing-legacy/what-changed-with-billing) until their plan ends, with 300 and 1,500 premium requests. Both reports are documented for API versions `2022-11-28` and `2026-03-10` with the same schema; the definition sends `2026-03-10`, which changed nothing for billing. Free and Student have unpublished allowances, so they are left to the Copilot API. The old `monthlyLimit` text setting (default 50, a premium request count) is gone rather than carried over: no saved number means the same thing in credits.
- **`grossQuantity` is the credits used, discounted or not.** An `ai_credit` item has `unitType: "ai-credits"` and `pricePerUnit: 0.01`; `grossQuantity` counts credits covered by the allowance as well as paid ones, so it is what the allowance is measured against. Credits are fractional; the card rounds.
- **A mapping never writes settings.** The old probe stored `apiReturnedEmpty` and the billing month, and cleared the manual value at month change. Now the plan's `allowance` and `unit`, and `manualUsage`, are handed to the script (`mapping.script.values`); a manual value is used only while GitHub reports no Copilot items, and nothing is stored back.
- **Left and Window laws.** Unlimited or no AI-credits quota is the plan with no card, not 100%; the plan is the account's tier, never its email. Billing's window is the calendar month GitHub names, in UTC; the Copilot API's is the month ending on its reset date.
- **The Copilot API already speaks credits.** Checked live on 2026-10-31 with a Student account: `copilot_internal/user` answers `token_based_billing: true` and a `quota_snapshots.premium_interactions` with `has_quota: true`, `entitlement` and `remaining` in AI credits (200 on Student), `credits_used`, and `quota_reset_date_utc` on the 1st. The wire name stays `premium_interactions`; `copilot-user.js` reads it unchanged.
- **The GitHub CLI's login.** The Copilot API's lookup ends with the `gh:github.com` Keychain item (go-keyring base64, `encoding: goKeyringBase64`); on Windows, go-keyring keeps it in Credential Manager as `gh:github.com:`, the token's bytes with no prefix, and the same lookup reads it; `gh`'s OAuth token answers `copilot_internal/user` but not the billing API (404), so Billing hands over to the Copilot API on no key or a refused one. The response's `login` is the account shown.
- **Compatibility.** The token moves from UserDefaults (or Keychain `github-copilot-token`) through `ProviderVault.legacyKeys`; the username is read from its old UserDefaults key and moves to `copilot.username` when saved; the old limit, a JSON number, reads as text. The old manual-override switch and value aren't carried over.

## Background

GitHub Copilot now bills usage as **AI Credits** instead of premium requests (see [usage-based billing docs](https://docs.github.com/en/copilot/concepts/billing/usage-based-billing-for-individuals)). All paid plans (Pro, Pro+, Max) get a monthly allowance measured in credits; one credit ≈ $0.01 of model spend. The previous "premium request" model is gone.

ClaudeBar currently shows Copilot as a "Session" card with strings like `"10/50 requests"`, `"CURRENT PREMIUM REQUEST USAGE"`, and `"MONTHLY PREMIUM REQUEST LIMIT"`. The card does not show a time-based reset countdown because neither probe populates `resetsAt`.

This plan renames the user-facing vocabulary and gives the card a proper "Monthly" identity with a "Resets in Xd" countdown.

---

## User Decisions (Confirmed)

1. **Quota type**: Use `QuotaType.timeLimit("Monthly")` — existing case, displayName "Monthly", duration 30 days.
2. **Reset date source**: Compute from current date (1st of next month, UTC). The internal API's `quotaResetDateUtc` is no longer used as the source of truth.
3. **Billing API endpoint**: Keep hitting `/users/{username}/settings/billing/premium_request/usage`. Only rename user-facing strings; the URL stays (GitHub has not yet deprecated it).
4. **Settings keys**: Keep `copilot.monthlyLimit`, `copilot.manualUsageValue`, etc. No JSON migration.

---

## Findings since

Facts about the two old probes, which the definition keeps:

- **Billing mode**: `GET https://api.github.com/users/{username}/settings/billing/ai_credit/usage` (or `premium_request/usage` for an annual plan still billed by request) with `Accept: application/vnd.github+json` and `X-GitHub-Api-Version`. It keeps `usageItems` whose `product` contains "copilot" (case-insensitive) and totals them. The response doesn't include an allowance, so the user picks a plan (`copilot.plan`, default Pro) that carries one. A 403 means the fine-grained PAT is missing **Plan: read**. A 404 means the user wasn't found or the token has no billing access.
- **Business/Enterprise can return empty `usageItems`** when the seat is provided by an org. The probe sets a "returned empty" flag, which the Settings card turns into a hint to try Copilot API mode, instead of turning on manual override automatically. "Zero usage" and "the API can't report usage" look the same in the response, so the probe doesn't treat one as the other.
- **Manual override** accepts a count or a percentage and is cleared when `timePeriod.{month,year}` in the response changes, i.e. when a new billing month starts.
- **Copilot API mode**: `GET https://api.github.com/copilot_internal/user` with a Classic PAT that has the `copilot` scope. It reads `quota_snapshots.premium_interactions`: `entitlement`, `remaining`, `percent_remaining`, `unlimited`. If there's no `premium_interactions`, it shows 100% "No AI credits quota". This endpoint is internal and undocumented, and it works on every plan type.
- **Token lookup** in both modes: the environment variable named in settings (from ClaudeBar's own process environment, not a login shell), then the stored token. The token is kept in `UserDefaults.standard` under `com.claudebar.credentials.github-copilot-token` and hasn't moved to the Keychain yet.
- **Reset date** is always the next 1st of the month at 00:00 UTC (`MonthlyResetDate`), including in Copilot API mode, where the API's own `quotaResetDateUtc` is ignored.
