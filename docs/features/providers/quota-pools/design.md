---
description: Contributor design for quota pools — a product's logins summed as one pool, "340% left across 3 logins". Which logins count, which share each brings, what is excluded and why, the sum-of-shares law and its one owner, and the popover's pool line. Read before touching Pool, Accounts.pool or the pool line.
---

# Quota pools: design

User guide: [README.md](README.md).

**Status: BUILT** — the `Pool` value, `Accounts.pool`, and the popover's
pool line.

| For | Read |
|---|---|
| the logins themselves — add, rename, pause, remove | [multiple accounts](../multi-account/design.md) |
| the words and the tree | [CANONICAL_MODEL.md](../../../architecture/CANONICAL_MODEL.md) |
| the policy that moves sessions inside the pool | [In use](../../in-use/design.md) |

## The moment

Mia keeps three Claude logins ([multiple accounts](../multi-account/design.md)):
*Personal 62%*, *Work 88%*, *Side 90%*, side by side on the product's page.
Each card answers for itself, so the family's room is arithmetic she does in
her head. She asks the one question the cards don't answer: *how much do we
have left, together?* — *the team has 240% left*.

## The one sentence

**A product's logins are one pool: the sum of what its unpaused logins have
left, each counted by the share it already shows — never a forecast, never a
percentage of anything bigger.**

The model already calls a product's logins *a pool* — interchangeable, the
healthiest one standing for the product ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)).
This feature lets the pool say its total. It adds one derived read beside
`status` · `best` · `cause`, owned by the same aggregate that owns those.

## What it sums — and what it doesn't

| Counted | Left out | Why |
|---|---|---|
| an **unpaused** login | a **paused** login | a paused login is out of every judgement already (CANONICAL §5): no refresh, no status, no alert, no say in its product's status — and no share |
| a login with a **knowable share** | a login with **no usage yet** | nothing seen, nothing to sum. The pool never guesses a share at zero or at a hundred; when a login has not reported, the family's total is what has been seen |
| the share the login **already shows** — its tightest window's, `Account.percentLeft`, the number its card leads with | a **balance with no ceiling** | a balance has no percentage ([the law on `Quota.left`](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)); writing 100% for it is the lie the status then believes. It stays on its own card, in dollars |
| the logins of **this product** | another **product's** logins | products are not interchangeable: one product's room never covers another's — the same reason the menu bar reads the worst product, not the average |

Two more decisions:

- **The pool exists from two shares.** One login's room is that login's
  own number, already on its card — printing it again as a pool would read
  as the login's quota and add nothing. Below two shares, `nil` — counted
  on the shares, not the unpaused logins, so two logins where one shows only
  a balance make no pool. `Pool` keeps this itself: `init?(shares:)` is
  `nil` below two.
- **The pool knows what it summed.** It carries one share per counted
  login, so the line can say *across 3 logins* honestly — that count is the
  sum's, never the page's, and a reader of the value can see exactly who
  was counted.

## The law that keeps it honest

> **A pool is a SUM OF SHARES.** Over 100% is fine and meaningful — three
> logins at 90% make 270% *of one window*, because the logins refill
> independently and each share is a fact about its own login. The pool is
> never a forecast and never a percentage of anything bigger: it says what
> is left now, and there is no whole behind it — not the plan, not a budget,
> not the family of products.

Owner: **`Pool`** keeps the law on the value and makes the sum;
**`Accounts.pool`** is the one place the shares are picked, each one the
login's own `percentLeft`. No view adds, rounds or re-decides a share — the
screen composes the sentence ("facts in the kernel; sentences in the App").

Why each share is the login's *tightest* window's: summing all of a login's
windows would add the same usage against different ceilings — 62% Session
plus 88% Weekly is not 150% of anything. One login, one share: the number it
already leads with.

## The pieces

```text
Accounts  ◆                       THE LOGINS — the sum sits beside its other reads
└── pool → Pool?  ◇               DERIVED — nil below two knowable shares
    │                             (each unpaused login's `percentLeft`)
    └── Pool  ◇                   THE SUM OF SHARES — a value, Sendable; it owns the sum
        │                         init?(shares:) — nil below two shares
        ├── shares: [Share]       one per counted login, in the person's login order
        │   └── Share  ◇          loginId (the lineup id) · percent — that login's share left
        ├── percent               THE SUM — over 100 is fine and meaningful
        └── count                 how many logins the sum spans

Account.percentLeft               THE SHARE A LOGIN BRINGS — its tightest window's;
                                  nil before a usage and for a balance with no ceiling

the product's page (App)          PoolText: "N% left across N logins" — the view renders it
```

| Piece | One job | Changes when |
|---|---|---|
| `Pool` (`Providers`) | the sum of shares, from two shares, and nothing else | the shape of the answer changes |
| `Account.percentLeft` (`Providers`) | the share one login brings — the one answer the pool, *Switch when low* and *In use* read | what a login's room is changes |
| `Accounts.pool` (`Providers`) | which logins count | what counts changes |
| `PoolText` (`App`) | the sentence and its tooltip | the words change |
| the pool line (`App`) | renders `PoolText` | the look changes |

## The tells

```swift
// App — the product's page, under the account chips
if let pool = tab.provider.accounts.pool { poolLine(pool) }
```

`PoolText` says the sentence; the view renders it. Neither sums, and
neither reads the logins to correct the pool.

## Composes with Switch when low

The pool and *Switch when low* answer different questions about the same
pool of logins. The pool says how much room the family has; the policy moves
new sessions inside it, one login at a time, by its own rules. The policy
compares each login's own share — the same `Account.percentLeft` the pool
sums — so *switch to the login with the most left* is decided by logins, not
by the family's average, and a login showing only a balance is never a
target: it has no percent to compare. A high pool and a depleted login in use
are both true at once, and the policy acts on the one it watches.

## Invariants — each law, its one owner

| Law | Owner |
|---|---|
| a pool is a SUM OF SHARES — never a forecast, never a percentage of anything bigger; over 100 is meaningful and said plainly | `Pool` |
| a paused login brings no share — one more consequence of the law on `isPaused`, kept here so the sum says so too | `Accounts.pool` |
| a login with no usage yet brings no share, and is never guessed at zero or at a hundred | `Accounts.pool` |
| a balance with no ceiling brings no share — it has no percentage to bring | `Account.percentLeft`, reading `Quota.percentLeft` |
| each login counts by the share it already shows — its tightest window's, the number its card leads with | `Account.percentLeft` |
| the pool exists from two shares; one login's room is that login's card, not a pool | `Pool` |
| two products' pools are never added — one product's room never covers another's | no caller: the pool answers for one product only |
| the line says the sum and names what it is across; it never recomputes it | `PoolText` (`App`) |

## Deferred

- **A pool across products** (*everything together*). Shares of different
  windows and different products added into one number is not a sum of
  existing facts — it needs a design of its own before it would be honest.
- **The pool as an alerting subject** (*the family is below 20%*). Thresholds,
  once-per-falling and the words are Alerting decisions; a destination would
  read `Accounts.pool` the way quota alerts read a login today.
- **The menu bar, the notch and Notify!** Each shows one number per product;
  where the pool belongs beside the login being watched is a per-surface
  layout question, not a domain one.
- **Naming the counted logins on the line** (a tooltip: *Personal 62% +
  Work 88% + Side 90%*). The value carries each share's login for exactly
  this; the page adds it when the line has earned it.
