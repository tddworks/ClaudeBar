---
description: Choose which Claude or Codex login new terminal sessions start with — switch by hand, get a nudge when it runs low, or let ClaudeBar switch. Use when you have personal and work logins and want the next `claude` on the one with room.
---

# In use: which login new sessions start with

With more than one Claude or Codex login ([multiple accounts](../providers/multi-account/README.md)), you choose which one your **next** `claude` or `codex` starts with, without signing out and in again. Sessions already running keep their login.

## Switch

Any of these:

- **Popover:** the login in use has an **IN USE** badge on its chip; every other login's chip ends in **Use**. One click switches. Right-clicking a chip has **Use for New Terminal Sessions** too.
- **Settings → Providers → Claude (or Codex) → Accounts:** the radio button on a login's row.
- **A link:** `open "claudebar://use?provider=claude&account=work"` ([URL schemes](../app/url-schemes/README.md)). The account is its name, its email or `default` for the plain login.

The login in use has a terminal mark on its chip.

## The one-time setup

The first time you choose a login other than the plain one, ClaudeBar shows the lines it will add to your shell, and asks first:

- **Add to ~/.zshrc**, **~/.bash_profile**, or a fish file of its own. ClaudeBar picks your login shell; you can choose another.
- **Copy — I'll Add It**, to put them in yourself.

The lines wrap `claude` and `codex` in small functions that read `~/.claudebar/in-use/claude` (or `codex`) on every run — one record per CLI. That file holds only the chosen login's folder, never a key. Tabs already open pick it up after `source ~/.zshrc`, or in a new tab.

**Turn it off:** **Settings → Accounts → Remove** next to *Shell set up*, or delete the block between `# >>> claudebar in-use >>>` and `# <<< claudebar in-use <<<`. Every CLI goes back to its own login.

## When the login in use runs low

When it drops below 20%, and another login has more left:

- the popover says so, with **Use for New Sessions**;
- a notification says so once, with the same button.

**Switch when low** (Settings → Accounts, off by default) does it for you. Below the percentage you pick (5–30%), new sessions move to the ticked login with the most left, and a notification says so, with **Undo**.

## Gotchas

- **Terminal only.** Claude Desktop, and IDE extensions that don't start from your shell, keep their own login.
- **An alias for `claude`** (Claude's local installer adds one) is replaced inside ClaudeBar's block by a function that runs the same program. Remove the block and your alias is back.
- Only logins that are a folder can be in use: the plain login, and logins added with *Sign in with browser* or *Choose Signed-in Folder*.
- Check your provider's terms before relying on *Switch when low* to move between logins.

## See also

- [Multiple accounts](../providers/multi-account/README.md)
- [Design](design.md), for contributors
