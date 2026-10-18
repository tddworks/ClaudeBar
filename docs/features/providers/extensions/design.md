---
description: How an extension's manifest is read as a definition and run, for contributors: the script fetch, the usage mapping, sections answering together, settings and the upgrade.
---

# Extensions: design

User guide: [README.md](README.md). Field reference: [manifest.md](manifest.md).

## Flow

An extension is a definition of origin *Extension*, run by the same `Provider` and `DataSource` as every other:

1. At launch `Extensions.catalog()` (Providers) reads each `~/.claudebar/extensions/<id>/manifest.json`; one that doesn't read is logged and left out.
2. `Extensions.definition(manifest:folder:)` makes the definition, id `ext-<id>`, `"together": true`:
   - `quotaGrid` / `costUsage` → a data source with **`Fetch.script`** (run from the extension's folder — with `/bin/sh` on the Mac, as the file itself on Windows, the `Processes` port's `script`; every config field as `CLAUDEBAR_<UPPER_SNAKE>`, secrets read from the vault) and **`Mapping.usage`** (the documented output);
   - `healthCheck` → an `http` HEAD request with nothing to map; failing is fetch health;
   - `dailyUsage`, `metricsRow`, `statusBanner` → skipped and logged.
   - config fields → provider-scope settings (`number` a text with a number pattern, `toggle` an On/Off choice).
3. `ExtensionSettingsUpgrade` (Infrastructure) moves what was saved before, once: values from `extensions.<id>.<field>`, secrets from UserDefaults into the vault.
4. `ProviderFactory.make` builds it like any custom provider; its logins join the lineup.

With `together`, every section runs on each refresh; the usage is their union in the manifest's order, a failed one is left out and shows as fetch health, and the refresh fails only when all do.

## Why some sections are no longer read

- `dailyUsage` printed ready-made totals; usage history reads raw records. An extension that wants daily usage writes JSON-lines records a `usageHistory` `files` glob reads, as every provider does.
- `metricsRow` free-form metrics and `statusBanner` free text have no domain meaning; the cost and daily cards every provider draws replace them, and a provider's status page is `profile.links.status`. Either can return as a general rule when an issue asks, problem first.

## Security

Scripts run as the person, with their permissions; *Import* and the docs say so. Secrets are passed as real environment variables of the child process (not on its command line, so not in `ps`), read from the Keychain vault scoped to the login.
