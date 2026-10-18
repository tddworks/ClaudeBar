## Why

<!-- The problem this solves, in the user's words — not the change. Link the issue.
     "Fixes #123: with two logins, the next session can't start on the one with room."
     If there is no issue, say what you saw and who it affects. -->

Fixes #

## Design

<!-- Where this lives in the design docs — they are the source of truth (AGENTS.md):
     CANONICAL_MODEL / TARGET_ARCHITECTURE section, or docs/features/<context>/<x>/design.md.
     If the design changed: what changed, and where it was confirmed (issue or PR comment).
     Write "No design change" when the code only catches up with the docs. -->

## What changed

<!-- The effect, briefly. The diff shows the how. -->

## How it was verified

<!-- Tests that pin the behaviour (Chicago school: state, not calls).
     For UI: before/after screenshots on mock data — scripts/demo-screenshots.sh, never real names, emails or usage. -->

## Checklist

- [ ] The problem is stated above, not only the solution
- [ ] Design docs updated, or no design change
- [ ] Tests added or updated; `xcodebuild test` passes
- [ ] User-visible change: one line under `## [Unreleased]` in `CHANGELOG.md`
- [ ] `python3 scripts/gen-docs.py && python3 scripts/check-docs.py --strict` passes
- [ ] No token, key, cookie or credential logged, committed or in a screenshot
