---
description: How user extensions are discovered, turned into providers and run, for contributors. Covers where each piece sits in the layers, how probe output maps onto existing domain models, the security model, and known gaps.
---

# Extensions: design

User guide: [README.md](README.md). Field reference: [manifest.md](manifest.md).

## Flow

At launch, after the built-in providers are registered, `ClaudeBarApp` creates an `ExtensionRegistry` and calls `loadExtensions(into: monitor)`:

1. `ExtensionRegistry` creates `~/.claudebar/extensions/` if it's missing.
2. `ExtensionDirectoryScanner` lists the folder's visible subfolders and parses each `manifest.json` with `ExtensionManifest.parse(from:)`. A folder whose manifest is missing or doesn't parse is dropped with no log line.
3. For each manifest, the registry builds one `UsageProbe` per section: a `ScriptProbe` for `probe.command`, or a `HealthCheckProbe` for `builtIn: "healthCheck"` + `url`.
4. It wraps them in an `ExtensionProvider` (an `AIProvider` whose id is `ext-<manifest id>`) and calls `QuotaMonitor.addProvider`.
5. `ProviderVisualIdentityLookup.registerExtensionIcons` records each manifest's `icon` if it's a valid SF Symbol, so the menu bar, popover, Touch Bar and Settings can show it.

Loading happens once, so adding or editing a manifest needs a relaunch. `ProvidersPane` falls through to `ExtensionConfigCard` for any `ExtensionProvider` whose manifest declares `config`.

## Layers

- **Domain**: the manifest and its parts (sections, config fields, colours), `ExtensionProvider`, `SectionData`, `ExtensionMetric` / `MetricDelta` / `StatusInfo`, `HealthCheckResult`, and the `ExtensionConfigRepository` port. The provider lives in Domain, like every other provider: it only merges snapshots and knows nothing about processes.
- **Infrastructure**: the scanner, the registry, both probes, and `JSONExtensionConfigRepository`.
- **App**: `ExtensionConfigCard` builds the settings UI from the manifest, and `ExtensionMetricCardView` draws metric cards. `AppSettings.extensionConfig` holds the repository.

### Reusing the existing models

`SectionData.decode(from:type:providerId:)` turns a script's JSON into the models built-in providers already use, so extensions get the existing cards at no extra cost:

| Section | Decodes to | Lands in `UsageSnapshot` as |
|---|---|---|
| `quotaGrid` | `[UsageQuota]` (`session` / `weekly` / `model:<name>` → `.modelSpecific` / anything else → `.timeLimit`) | `quotas` |
| `costUsage` | `CostUsage` | `costUsage` |
| `dailyUsage` | `DailyUsageReport` | `dailyUsageReport` |
| `metricsRow` | `[ExtensionMetric]` | `extensionMetrics` |
| `statusBanner` | `StatusInfo` | **nothing** (see Known gaps) |
| `healthCheck` | `HealthCheckResult.toExtensionMetrics()`, from `HealthCheckProbe` rather than a script | `extensionMetrics` |

`ExtensionMetric` was the one new card model. It has since grown an optional `group`, which other providers use for grouped rows (Oh My Pi accounts). Extension metrics leave it nil and render in the flat grid, so older extension JSON keeps working.

### Merging sections

`ExtensionProvider.refresh()` runs every section's probe in a task group. Failed sections are dropped, and the rest are merged: quotas and metrics are concatenated, and the last cost and daily report win. It throws `ProbeError.noData` only when every section failed, so one broken script doesn't blank the provider. The cost is that a failing section's error is thrown away, which is why the README tells authors to debug scripts by hand.

`isAvailable()` is true when any probe is available: a script file exists at the resolved path, or the section is a health check, which is always available. `QuotaMonitor` skips refreshing providers that aren't available.

## Running a script

`ScriptProbe` resolves `probe.command` against the extension folder (unless it starts with `/`) and runs it through `DefaultCLIExecutor` as `/bin/sh -c <command>`, with the extension folder as the working directory. When config values exist, the command becomes `env CLAUDEBAR_X='…' CLAUDEBAR_Y='…' <path>`. Values are single-quoted with `'` escaped, and they're never embedded in the script's arguments.

`ConfigField.environmentVariableName` inserts `_` between a lowercase letter and a following uppercase letter, maps `-` to `_`, and uppercases the result. Values come from `allValues(forExtensionId:fields:)`: the stored value, else the field's `default`. Non-secrets live in `settings.json` under `extensions.<id>.<fieldId>`. Secrets live in `UserDefaults.standard` under `com.claudebar.credentials.ext-<id>-<fieldId>`, the same kind of store most built-in provider tokens still use, not the Keychain (`KeychainCredentialRepository`) that the Notify! token uses.

`DefaultCLIExecutor` wraps `InteractiveRunner`, which was built for interactive CLIs, and it shows:

- **PTY, not pipes.** stdout and stderr go to the same pseudo-terminal, so anything a script writes to stderr ends up in the JSON.
- **Idle cutoff.** Once meaningful output has arrived, 3 s with no new output ends the capture. No `CLICompletionRule` is passed for extensions, so a script that prints a line and then waits on the network is cut off.
- **Timeout** is `probe.timeout`, default 10 s.

A plain `Process` with separate pipes, waiting for exit, would suit scripts better.

## Security

- Scripts run as the user, never elevated, and only produce data on stdout. Nothing the script prints is executed or evaluated by the app, only decoded as JSON into fixed types.
- The timeout stops scripts that hang.
- The `ext-` prefix keeps an extension from taking over a built-in provider's id and its `providers.<id>.*` settings.
- Config values are passed as environment variables, never as the script's own arguments. They are, however, written into the `sh -c "env VAR='…' <path>"` command line, so while a probe runs, secrets included, they're visible to the user's other processes through `ps`. Passing them in `Process.environment` instead would close that.
- Extensions are unsigned, user-installed code. ClaudeBar doesn't sandbox them, so installing one means trusting it the way you'd trust any shell script.

## Known gaps

Each of these is written up for users in the README's Gotchas or in manifest.md until it's fixed:

| Gap | Where | Fix |
|---|---|---|
| `probe.interval` is parsed into `refreshInterval` but nothing reads it. Every section runs on each app refresh | `ExtensionSection`, `ExtensionProvider.refresh` | Per-section scheduling in the provider, or remove the field |
| `statusBanner` output is decoded, then dropped, because `UsageSnapshot` has no status field | `ScriptProbe.sectionDataToSnapshot` | Add a status to the snapshot and a banner view |
| The command path isn't quoted, so a path with spaces breaks. A command with arguments fails the `isAvailable` file check | `ScriptProbe.buildCommand` / `resolveScriptPath` | Quote the path, and split arguments off before the file check |
| stderr is merged into the JSON, and there's a 3 s idle cutoff | `DefaultCLIExecutor` / `InteractiveRunner` | Pipes, and wait for exit |
| Invalid manifests are skipped silently | `ExtensionDirectoryScanner.scan` | Log the parse error with the folder name |
| A section's error is discarded | `ExtensionProvider.refresh` | Keep the error per section and show it |
| `required` isn't enforced, and `colors.gradient` isn't used | `ExtensionConfigCard` | Mark missing required fields; use the gradient for the provider's accent |
| Secrets are in UserDefaults, not the Keychain, and they're visible in `ps` while a probe runs | `JSONExtensionConfigRepository`, `ScriptProbe.buildCommand` | `KeychainCredentialRepository`, and the environment instead of the command line |

## Testing

The Domain tests cover manifest parsing (including config fields and defaults), environment variable names, `SectionData` for every section type, `HealthCheckResult` status rules, and `ExtensionProvider` merge and availability. The Infrastructure tests cover `ScriptProbe` (execution, parsing, errors and env var injection through a mocked `CLIExecutor`), `HealthCheckProbe`, the config repository, and the directory scanner. They live in `Tests/DomainTests/Extension/` and `Tests/InfrastructureTests/Extension/`.
