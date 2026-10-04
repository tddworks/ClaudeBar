---
description: DeepSeek's JSON definition, exact balance mapping, independent API-key accounts, verified legacy-key migration, and the compatibility boundary for its existing settings card.
---

# DeepSeek as a definition

This is the first HTTP/API-key migration in [#331](https://github.com/tddworks/ClaudeBar/issues/331),
following the shared account design shipped in #366. It adds no account adapter
and no vendor-named Swift inside a module.

```text
deepseek.json ──► Provider owns default + added Accounts
                      │
                      ├── credential: environment → setting (default)
                      └── accounts.patch: setting only (added login)
                                      │
                             account-scoped ProviderVault
                                      │
                          HTTP GET /user/balance
                                      │
                          deepseek-balance.js
                                      │
                        Left.money(amount, currency), no ceiling/window
```

| Component | Responsibility | Input → output |
|---|---|---|
| Definition | Identity, look, endpoint, lookup order, account form and patch | JSON → generic Provider |
| Provider | Existing lifecycle, account IDs, saved configurations, names and pins | Account → scoped DataSources |
| HTTP worker | Generic Bearer request, timeout, authentication and rate-limit handling | Credential → Response |
| Script mapper | Generic money or percentage output, one measure per quota | Script output → UsageSnapshot |
| Balance script | Primary currency, decimal strings, paid/granted subtitle, validation | API response → money quota or error |
| ProviderVault | Account-scoped keys and verified default-login migration | Named key → credential |

## Response mapping

The [balance API](https://api-docs.deepseek.com/api/get-user-balance/) returns
decimal strings in `balance_infos`. As before, the first entry supplies the
billing currency; a later USD entry never replaces a first CNY entry. The
required total remains a string through JavaScript and is decoded to Swift
`Decimal`. The optional paid/granted amounts are formatted only for the
subtitle. No cap, percentage, reset or window is fabricated.

The generic script-output contract now accepts either `percentRemaining` or
`left: { money, of?, currency? }`, exclusively. Decimal strings preserve the
amount exactly; numeric output remains accepted, and omitted currency defaults
to USD. Existing percentage/cost scripts keep their format. The script sees no
credential fields and has no I/O. This small script keeps the paid/granted
formatting and response validation beside the definition.

An empty balance list is `noData`; malformed required fields are `parseFailed`.
`is_available: false` becomes an explicit failure, including for a positive
balance. Unlike the legacy placeholder percentage, it cannot label unusable
funds healthy. The generic Provider retains a previous successful snapshot
on this failure. HTTP 401/403 remain authentication failures; 429 uses the
shared retry policy.

## Credential compatibility

The default key is `provider.deepseek.apiKey`. `ProviderVault` reads the old
`com.claudebar.credentials.deepseek-api-key` UserDefaults entry only for that
exact default key, using `SecureCredentialMigration`: secure storage wins,
a legacy key is removed only after read-back confirms its write, and a refused
migration preserves and returns the old key. Secure deletion must succeed
before the legacy copy is removed. No secret enters `settings.json`.

The existing Default Account card uses that same vault. Its configurable
environment-variable name is preserved by the App's injected environment
lookup, read at lookup time so an edit takes effect without restarting. An
empty name means `DEEPSEEK_API_KEY`; a nonempty variable wins over the saved
default key. This outer compatibility boundary and the settings sub-protocol
remain until the generic settings-form migration (architecture slice 3).

An added login changes the credential rule to `setting: apiKey` and reads
`provider.deepseek.<UUID>.apiKey`. It never reads a process environment key or
the default-login migration entry. `accounts.form` drives the existing shared
Add Account, rename, pause, reorder, pin and remove flows. Account configuration
stores identity/origin, not the key. Explicitly adding a key-based account
activates that login, even though the unconfigured default starts disabled;
a later pause remains saved across relaunches.

## Validation

`DeepSeekDefinitionTests` exercise the bundled definition through real generic
workers with stubbed network and vault ports: first currency, exact money,
breakdowns, unavailable funds, zero/negative balances, request/authentication,
empty/malformed responses, environment precedence, separate keys, relaunch and
missing-key isolation. Storage tests use independent test stores, including a
refusing secure store. Generic script-money tests cover exact money, a ceiling,
existing percentage output and missing/ambiguous/invalid measures. Shared
account-copy tests cover API-only login and recovery descriptions.

Live sign-ins, the system Keychain's production signing permissions and
real two-account billing responses require user acceptance after release.
