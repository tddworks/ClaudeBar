---
description: Track today's AWS Bedrock spend, token counts and per-model costs from CloudWatch, against an optional daily budget. Use when setting up Bedrock with an AWS profile or when it shows no data.
---

# AWS Bedrock

Shows what you've spent on Bedrock today (since local midnight), with input and output tokens and a per-model cost breakdown. Set a daily budget to also get a percentage, a status color and alerts.

## Setup

1. Make sure you have AWS credentials that can read CloudWatch in your Bedrock regions (see [Permissions](#permissions)). For an SSO profile, run `aws sso login --profile <name>`.
2. Settings → Providers → AWS Bedrock: turn it on. It's **off by default**.
3. Click AWS Bedrock and fill in **AWS Bedrock Configuration**:
   - **AWS PROFILE NAME**: the profile from `~/.aws/config`. Leave it empty to use the AWS SDK's default credential chain (environment variables, the `default` profile).
   - **REGIONS (COMMA-SEPARATED)**: where you call Bedrock, e.g. `us-east-1, us-west-2`. Defaults to `us-east-1`.
   - **DAILY BUDGET (USD, OPTIONAL)**: turns today's spend into a percentage of the budget.
4. **Quit and reopen ClaudeBar** after setting or changing the profile name (see Gotchas).

## Permissions

These are AWS IAM permissions, not macOS ones:

- `cloudwatch:ListMetrics` and `cloudwatch:GetMetricStatistics` in each configured region, **and in `us-east-1`**, where ClaudeBar checks your credentials.
- `pricing:GetProducts` (optional). Without it, costs use prices bundled with ClaudeBar.

## Gotchas

- **Changing the profile name needs a restart.** The profile is read once when ClaudeBar starts. Regions and budget changes apply on the next refresh.
- **A named profile is resolved as an AWS SSO profile.** If your profile uses static access keys and nothing shows, clear the profile name and provide the keys through the default credential chain instead.
- **Nothing shows at all** means the credential check failed: ClaudeBar couldn't list CloudWatch metrics in `us-east-1` with your credentials. Bedrock is then skipped silently, with no error. The usual causes are an expired SSO session (run `aws sso login` again), a wrong profile name, or missing `us-east-1` permissions. The log has the AWS error.
- **"No AWS regions configured for Bedrock monitoring"** means the regions field is empty.
- **A region that fails is skipped**, and the others still count. If every region fails, or none has usage today, the card shows no usage rather than an error.
- **Costs are estimates**: CloudWatch token counts × the price per million tokens from the AWS Pricing API (cached for a day), else the bundled price table. A model with no known price shows $0.
- **Without a daily budget there's no percentage or status color** for Bedrock, and no alerts. The popover card still shows the cost and tokens.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Kiro](../kiro/README.md)
