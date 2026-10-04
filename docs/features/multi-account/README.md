---
description: Track more than one Claude or Codex login side by side — sign in with your browser or choose a signed-in folder, name each account, pin them to the menu bar, and sign in again when a session expires. Use when you have personal and work accounts.
---

# Multiple accounts

Claude and Codex can each watch more than one login: a personal and a work account, or two ChatGPT workspaces under one email. So can an API provider you made with **Add Provider**: each account has its own key. Every account has its own quotas, refreshes, pause switch and errors. The other built-in providers have one account for now.

## Add an account

Open **Settings → Providers → Claude** (or **Codex**) **→ Accounts → Add Account**, then pick one of two ways:

- **Sign in with browser.** ClaudeBar makes a new folder for this login and runs the provider's own sign-in in it (`claude auth login`, or `codex login`). Finish signing in in your browser. Your usual login isn't touched.
- **Choose Signed-in Folder.** Pick a folder a login already lives in. For Claude that's a `CLAUDE_CONFIG_DIR` folder; for Codex it's a `CODEX_HOME` folder that uses file credential storage (`cli_auth_credentials_store = "file"`).

ClaudeBar then checks the login before keeping it:

1. **Found a login:** the folder holds a key.
2. **Signed in as …:** the email it belongs to. A login that's already listed, or that is your usual login, is refused.
3. **Fetched usage:** the first refresh. If only this step fails (for example, you're offline), you can **Add anyway**, and the account shows **Re-auth** until it works.

Last, you can give the account a name, such as *Work*. Leave it empty to show its email.

For an API provider you made, **Add Account** asks for the account's **API key** instead. The key is kept in your Keychain under that account only. An account without a key of its own shows *Key needed*; it never borrows your first account's key, or one in an environment variable.

Don't copy an existing `auth.json` or `.credentials.json` to make a second login. Sign in separately, so each login refreshes its own session.

## See them side by side

- In the popover, a provider with several accounts is one tab. Its accounts appear one below another, each with its own quotas. The **ACCOUNTS** chips at the top hide an account from this view only; it keeps refreshing and alerting. When an account makes the provider's status a warning, a line at the bottom names it, for example *"Work is at 18% Session — causing Warning"*.
- **Settings → Providers → Claude → Accounts** lists every login. Drag to reorder, use **⋯** to rename, pause or remove one, and click the pin to show it in the menu bar.
- With one account, the provider is called by its name ("Codex"). With several, each shows the name you gave it, or its email.
- In the menu bar, each pinned account gets a short name beside the icon: up to 12 characters of the name you gave, or up to 8 of the part of its email before the @. Names that would look alike are numbered (`work·1`, `work·2`). The tooltip shows the full name. Accounts count toward the three-entry menu bar limit.

The data source choice (for example RPC or API) applies to every account of a provider. Each added account runs it against its own folder, and its failures never fall back to your usual login's session.

## Remove or sign in again

**Remove** forgets the account in ClaudeBar and drops it from the menu bar:

- An account you added with **Sign in with browser** has its folder deleted too, since ClaudeBar made that folder and nothing else uses it.
- An account added with a key has its key deleted from your Keychain.
- A folder you chose stays exactly where it is.
- Your usual login can't be removed.

When a session expires, the account shows **Re-auth**:

- For an account ClaudeBar signed in to, the button runs the sign-in again in the same folder.
- For a folder you chose, ClaudeBar shows the command to run yourself.

If a different person signs in to that folder, ClaudeBar refuses to show their usage under the old account. Remove it and add the new login instead.

## See also

[Claude setup](../../providers/claude/README.md) · [Codex setup](../../providers/codex/README.md) · [Settings storage](../../settings.md) · [Design (contributors)](design.md)
