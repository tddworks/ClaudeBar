---
description: Track GitHub Copilot monthly AI credits through the GitHub Billing API or the Copilot internal API, using a personal access token. Use when setting up Copilot or when it shows no data on a Business or Enterprise plan.
---

# Copilot

Shows your GitHub Copilot AI credits (formerly premium requests) for the current month as a Monthly quota. It resets at 00:00 UTC on the 1st of each month.

## Setup

Copilot is **off by default**, because it needs a token.

1. Settings → Providers → Copilot: turn it on.
2. Under **GitHub Copilot Configuration → Probe Mode**, pick a mode (see below).
3. Create the token that mode needs. The pane links to **Create fine-grained token** or **Create classic token**.
4. Paste it into **Personal Access Token**. In Billing mode, also fill in **GitHub Username**.
5. Press **Save & Test Connection**.

## Probe modes

| Mode | Needs | Pick it when |
|---|---|---|
| Billing (default) | Fine-grained PAT with **Plan: read**, plus your GitHub username | Individual plans (Free, Pro, Pro+) |
| Copilot API | Classic PAT with the **copilot** scope | Business or Enterprise, or whenever Billing mode shows no data |

Billing mode counts the Copilot items in your monthly billing usage and compares them against **Monthly AI Credits Limit**: Free/Pro (50), Business (300), Enterprise (1000) or Pro+ (1500). Pick your plan's allowance, because the Billing API doesn't return one. Copilot API mode reads your allowance and remaining credits straight from GitHub, so those settings are hidden in that mode.

## Gotchas

- **"API returned no usage data"** is common for org-provided Copilot Business subscriptions, where the Billing API has nothing to report. Switch to Copilot API mode. In Billing mode you can also turn on **Enable manual usage entry** and type the number from GitHub, as a count (`99`) or a percentage (`198%`). The manual value is cleared when a new billing month starts.
- **Using an environment variable instead of pasting the token.** Put the variable's name in **Auth Token Env Var (Alternative)**. ClaudeBar checks that variable first and falls back to the pasted token. It reads ClaudeBar's own environment, so a variable exported only in your shell profile isn't visible when ClaudeBar starts from Finder or at login.
- **"Forbidden - ensure PAT has 'Plan: read' permission"** (Billing) or **"Forbidden - ensure Classic PAT has 'copilot' scope"** (Copilot API) means the token type doesn't match the mode. A fine-grained token doesn't work for Copilot API mode.
- **"No Copilot subscription found"** (Copilot API mode, HTTP 404) means the token's account has no Copilot seat.
- **Unlimited or no AI credits quota** shows as 100% with "Unlimited AI credits" or "No AI credits quota".
- **Over the limit.** Billing mode lets the remaining percentage go negative, so you can see how far over you are.
- **The token is stored in ClaudeBar's app preferences (UserDefaults)**, not the Keychain and not `settings.json`. **Remove Token** deletes the token and the username.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
