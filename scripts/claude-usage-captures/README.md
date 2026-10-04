# `/usage` capture corpus

50 real `claude /usage` PTY captures, 25 that reached a finished Usage screen and
25 that were still the CLI's boot screen. They are the evidence behind the claims
in `docs/providers/claude/design.md` about how `CLICompletionRule` behaves, and
they are what `scripts/replay-claude-usage-captures.sh` replays.

Each file is one capture: the bytes the PTY produced between one
`Starting Claude probe with /usage command` and the next, escape sequences and
all. Keeping the escapes is the point — a TUI redraw writes every word run at its
own absolute column, so `Current session` reaches the PTY as
`Curre␛[10Gt␛[12Gsession` and a search for the literal phrase finds nothing.

`boot-NNN` and `settled-NNN` are the class the file belongs to, assigned by
whether the capture painted a quota bar (`38% used` / `12% left`) — data only a
finished Usage tab has.

## Provenance and redaction

Extracted from a user's `ClaudeBar.log` with

```bash
scripts/replay-claude-usage-captures.sh --extract <ClaudeBar.log> --out <dir> --all
```

and redacted by the same script, which replaces credentials, authorization
headers, OAuth material, JWTs, email addresses, the account holder's first name,
timezone identifiers, session ids, home directories and URL query strings.
Patterns are matched against a copy of the capture in which every escape sequence
is blanked, so a value the CLI wrote across a cursor jump is still found.

Not redacted, because none of it identifies a person: the probe's own working
directory (`~/Library/Application Support/ClaudeBar/Probe`, the same on every
machine and part of the boot screen), the CLI's version banner and release-note
text, and the output of whatever plugins the account runs.

The committed set is a balanced subset — 25 of each class. Pass `--all` to
rebuild all 430 from a log.
