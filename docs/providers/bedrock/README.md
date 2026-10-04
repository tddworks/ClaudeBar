---
description: Track today's AWS Bedrock spend, token counts and per-model costs from CloudWatch, against an optional daily budget. Use when setting up Bedrock with an AWS profile or when it shows no data.
---

# AWS Bedrock

Shows what you've spent on Bedrock today (since local midnight) as one cost card, with a line per model (tokens and calls on hover). Set a daily budget to see the spend against it, with an on-track / near-limit / over-budget badge.

## Setup

1. Make sure you have AWS credentials that can read CloudWatch in your Bedrock regions (see [Permissions](#permissions)). For an SSO profile, run `aws sso login --profile <name>`.
2. Settings → Providers → AWS Bedrock: turn it on. It's **off by default**.
3. Click AWS Bedrock and fill in its settings:
   - **AWS Profile**: the profile from `~/.aws/config`. Leave it empty to use the AWS SDK's default credential chain (environment variables, the `default` profile).
   - **Regions**: where you call Bedrock, comma-separated, e.g. `us-east-1, us-west-2`. Defaults to `us-east-1`.
   - **Daily Budget (USD)**: optional; the cost card then judges today's spend against it.

## Permissions

These are AWS IAM permissions, not macOS ones:

- `cloudwatch:ListMetrics` and `cloudwatch:GetMetricStatistics` in each configured region.
- `pricing:GetProducts` (optional). Without it, costs use prices bundled with ClaudeBar.

## Gotchas

- **Settings apply on the next refresh**, profile included; no restart.
- **A named profile is resolved as an AWS SSO profile.** If your profile uses static access keys and nothing shows, clear the profile name and provide the keys through the default credential chain instead.
- **An AWS error on the card** (an expired SSO session, a wrong profile name, missing permissions) means every region failed; the first region's error is the one shown. Run `aws sso login` again for an expired session. A region that fails while another answers is skipped, and logged.
- **"No regions configured"** means the Regions field is empty.
- **Costs are estimates**: CloudWatch token counts × the price per million tokens from the AWS Pricing API (cached for a day), else the bundled price table. A model with no known price shows $0.
- **The budget is never a quota.** Older versions showed a "Daily Budget" quota card; spend is now one cost card judged by the budget, and without a budget it shows the spend alone.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Kiro](../kiro/README.md)
