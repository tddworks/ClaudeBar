# MiniMax: probe design

Research notes for the MiniMax Coding Plan probe, from the code, [#115](https://github.com/tddworks/ClaudeBar/pull/115), [#128](https://github.com/tddworks/ClaudeBar/pull/128) and the unmerged [#266](https://github.com/tddworks/ClaudeBar/pull/266).

## Source

`GET <api base>/v1/api/openplatform/coding_plan/remains` with `Authorization: Bearer <key>`.

| Region | API base | Platform (dashboard, keys) |
|---|---|---|
| International | `https://api.minimax.io` | `https://platform.minimax.io` |
| China | `https://api.minimaxi.com` | `https://platform.minimaxi.com` |

The first version hard-coded the China host, so international keys failed ([#125](https://github.com/tddworks/ClaudeBar/issues/125)). The region picker was added in 0.4.38; China is still the default.

HTTP 401/403 → "Authentication required"; any other non-200 → "MiniMax API returned HTTP N".

## Response

Shape (values illustrative):

```json
{
  "base_resp": { "status_code": 0, "status_msg": "…" },
  "model_remains": [
    { "model_name": "…", "current_interval_total_count": 1500,
      "current_interval_usage_count": 1459, "remains_time": <number>, "end_time": <epoch ms> }
  ]
}
```

- `base_resp.status_code` ≠ 0 → "MiniMax API error: `<status_msg>`".
- Empty or missing `model_remains` → "No usage data available".
- One quota per model, labelled with `model_name`.
- `end_time` is epoch **milliseconds** and becomes the reset time. `remains_time` is decoded but unused.

### `current_interval_usage_count` is the remaining count

Despite the name, it is what's **left**, not what's used. This was confirmed against the MiniMax dashboard: at "3% used" the API returned `usage_count=1459` of `total=1500`. The probe clamps it to `0…total`, shows `total − usage_count` as used, and `usage_count / total` as percent remaining.

A model with `current_interval_total_count` 0 shows 0% remaining.

## Lead: the token-plan endpoint (not merged)

[#266](https://github.com/tddworks/ClaudeBar/pull/266) (closed without merging, 2026-08-25) reported that current plans use `GET <api base>/v1/token_plan/remains`. Its responses carry percentages, and the count fields can be 0:

- `current_interval_remaining_percent`
- `current_weekly_remaining_percent`
- `weekly_start_time` / `weekly_end_time` (epoch ms), next to `start_time` / `end_time`

The PR showed the more restrictive of the interval and weekly windows, and fell back to counts when no percentage was present. Nobody has checked this here. If users report 0% on every model, look at this first.
