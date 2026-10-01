# Amp Code: probe design

How the Amp probe reads `amp usage`, from the code and commit history (Feb–Mar 2026).

## Source

`amp usage --no-color`, located through the login-shell PATH, 8-second timeout. A non-zero exit code is an error; stdout is parsed line by line. There is no API call and ClaudeBar stores no Amp credential: the CLI's own sign-in is used.

## Output format

As seen in March 2026:

```
Signed in as user@example.com (username)
Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://...
Individual credits: $0 remaining - https://...
```

| Line | Pattern | Becomes |
|---|---|---|
| Account | `Signed in as <email> (` | account email (redacted to `u***@domain` in logs) |
| Capped credit | `<label>: $<left>/$<total> remaining` | percentage quota, reset text `$left/$total` |
| Balance | `<label>: $<left> remaining` | dollar-balance quota (no percentage) |

- Labels are mapped: `Amp Free` → "Free", `Individual credits` → "Individual". Any other label is kept as printed, so a new credit type still shows up.
- Everything after `remaining` (replenish rate, bonus, URL) is ignored. There is no reset time in the output, so none is shown.
- No matching line at all → "No valid credit lines found in amp usage output".

## Dead end: plan tier

The first version (0.4.28) derived a plan tier ("Free") from the credit labels. It was removed in 0.4.41: Free and Individual credits are separate balances that can exist side by side, not tiers of one plan, so no single tier label is correct.
