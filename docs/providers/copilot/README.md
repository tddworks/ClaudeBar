---
description: Track GitHub Copilot monthly AI credits through the GitHub Billing API or the Copilot internal API, using a personal access token. Use when setting up Copilot or when it shows no data on a Business or Enterprise plan.
---

# Copilot

Shows your GitHub Copilot AI credits (formerly premium requests) for the current month as a Monthly quota. It resets at 00:00 UTC on the 1st of each month.

## Setup

Copilot is **off by default**, because it needs a token.

1. Settings → Providers → Copilot: turn it on.
2. Signed in to the GitHub CLI (`gh auth login`)? That's enough: with no token saved, Copilot reads your AI credits through the Copilot API with `gh`'s login. macOS may ask once to let ClaudeBar read the `gh:github.com` Keychain item.
3. Otherwise pick the **Data fetching method** under **Copilot Configuration** (see below), create the token it needs and paste it into **GitHub Token**. On Billing, also fill in **GitHub Username** and **Monthly AI Credits**.

## Data sources

| Data source | Needs | Pick it when |
|---|---|---|
| Billing API (default) | Fine-grained token with **Plan: read**, plus your GitHub username | Individual plans (Free, Pro, Pro+) |
| Copilot API | Classic token with the **copilot** scope, or the GitHub CLI's login | Business or Enterprise, or whenever Billing shows no usage |

Billing hands over to the Copilot API when it has no token or GitHub refuses it. Billing counts the Copilot items in this month's billing usage against **Monthly AI Credits**: Free/Pro (50), Business (300), Enterprise (1000) or Pro+ (1500). Enter your plan's allowance, because the Billing API doesn't return one. The Copilot API reads your allowance and remaining credits straight from GitHub, and shows your plan.

## More than one account

**Accounts → Add Account** asks for what the active data source needs: a token, plus a username and monthly allowance on Billing. An added account never reads the environment variable.

## Gotchas

- **Billing shows 0 used on an organization seat.** The Billing API has nothing to report for org-provided Business seats. Switch to the Copilot API, or fill in **Used This Month** with the number from GitHub, as a count (`99`) or a percentage (`198%`). It's used only while GitHub reports no usage, and isn't cleared for you when a new month starts.
- **"Authentication required" with a token saved** means GitHub refused it (expired or revoked). A saved token comes before the GitHub CLI's login, so **Clear** it to fall back to `gh`, or paste a new one.
- **Using an environment variable instead of pasting the token.** ClaudeBar reads `COPILOT_TOKEN`, or the name you put in **Environment variable**, before the pasted token. It reads ClaudeBar's own environment, so a variable exported only in your shell profile isn't visible when ClaudeBar starts from Finder or at login.
- **"Forbidden - ensure the token has 'Plan: read' permission"** (Billing) or **"Forbidden - ensure the classic token has the 'copilot' scope"** (Copilot API) means the token type doesn't match the data source. A fine-grained token doesn't work for the Copilot API.
- **"No Copilot subscription found"** (Copilot API, HTTP 404) means the token's account has no Copilot seat.
- **Unlimited, or no AI credits quota**, shows your plan and no card, rather than a 100% one.
- **Over the limit.** Billing lets the remaining percentage go negative, so you can see how far over you are.
- **The token lives in the Keychain** (moved there from app preferences the first time it's read).

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
