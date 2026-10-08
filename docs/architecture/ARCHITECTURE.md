---
description: The map of ClaudeBar's design — five documents read in order, from the person's question to how each case runs, why that order, and which one to open for a change; start here before any design or code change.
---

# ClaudeBar — architecture

ClaudeBar is a macOS menu bar app that shows how much of each AI coding
quota is left. Its modules are one Swift package that also builds on Windows,
for the community's *ClaudeBar for Windows*
([MODULAR_DESIGN §10](MODULAR_DESIGN.md#10--one-package-two-platforms)).
Its design is five documents. **Each answers a question that
only exists once the one before it is answered**, so they are read in order,
and a later one may cite an earlier one, never the reverse.

| # | Document | Answers |
|---|---|---|
| 1 | [USER_JOURNEYS.md](USER_JOURNEYS.md) | **Who is asking, and what?** The people, the moments, the words each screen prints |
| 2 | [CANONICAL_MODEL.md](CANONICAL_MODEL.md) | **What is true?** The tree of what a person can point at, each law and its one owner |
| 3 | [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) | **How does it run?** The pieces, each with one job, and the flows |
| 4 | [MODULAR_DESIGN.md](MODULAR_DESIGN.md) | **Where does the code live?** The modules and what each may import |
| 5 | [ENGINE_DESIGN.md](ENGINE_DESIGN.md) | **How does each case work?** Every fetch, credential, setting and CLI rule a definition can use |

Then outward, one per thing: `docs/features/<x>/design.md` and
`docs/providers/<id>/design.md` apply the five to one feature or one vendor,
and hold only what is that thing's own — its research, its quirks, its laws.

## Why this order

1. **Everything answers a person.** A law with no moment behind it in #1
   solves a problem nobody has. A change starts by naming the person and the
   moment that breaks.
2. **Each step needs the one before.** Words and laws (#2) exist to answer the
   questions (#1). A piece (#3) is the owner of a law made concrete. A module
   (#4) packages pieces that exist. A case (#5) lives inside a piece and a
   module that are already there.
3. **Change flows downhill.** What people ask changes least; cases change most.
   A change to one document can only move the ones after it, never back up.
   When a later document needs a new word or law, the earlier one changes
   first — that is the design leading the code.

**One home per fact.** A document never restates an earlier one's word, law
or piece; it links back. A fact that appears in two of them is a bug in the
docs.

## Where a change starts

| You are… | Start at | Then |
|---|---|---|
| fixing a bug or reviewing a PR | #1 — which moment breaks, for whom? | the law (#2), its owner (#3) |
| adding a feature or a screen | #1, with a mockup in `design-concept/<x>/` | #2 → #3, then the feature's `design.md` |
| adding a provider | a similar provider's `design.md` | #5 for the cases it can use |
| adding a fetch, credential or setting case | #5 | #2 if it needs a new law |
| adding a file, type or module | #4 | #3 for the piece it belongs to |
