---
description: Add your own quota source to ClaudeBar with a manifest.json and a script that prints JSON, in ~/.claudebar/extensions/. Use when writing an extension or when one doesn't show up.
---

# Extensions

An extension adds a provider to ClaudeBar without changing the app. You create a folder in `~/.claudebar/extensions/` with a `manifest.json` and one or more scripts. Each script prints JSON, and ClaudeBar shows it as quota cards, a cost card, daily usage cards or metric cards, next to the built-in providers. A built-in health check can also ping a URL with no script at all.

The full field reference is in [manifest.md](manifest.md). A working example with every section type is in [example-provider/](example-provider/).

## Quick start

```bash
mkdir -p ~/.claudebar/extensions/my-provider
cd ~/.claudebar/extensions/my-provider

cat > manifest.json <<'EOF'
{
  "id": "my-provider",
  "name": "My Provider",
  "version": "1.0.0",
  "icon": "cpu.fill",
  "config": [
    { "id": "apiKey", "label": "API Key", "type": "secret", "placeholder": "sk-..." }
  ],
  "sections": [
    { "id": "quotas", "type": "quotaGrid", "probe": { "command": "./probe.sh", "timeout": 10 } }
  ]
}
EOF

cat > probe.sh <<'EOF'
#!/bin/sh
curl -s -H "Authorization: Bearer $CLAUDEBAR_API_KEY" https://api.example.com/usage \
  | jq '{quotas: [{type: "weekly", percentRemaining: (.remaining / .limit * 100)}]}'
EOF
chmod +x probe.sh
```

Then:

1. **Quit and reopen ClaudeBar.** Extensions are loaded only at launch.
2. **Settings → Providers → My Provider** shows a **My Provider Configuration** card with the fields your manifest declares. Enter the API key there.
3. The provider appears in the popover like any other and refreshes with the rest (**Settings → Sync & Alerts** sets how often).

To try the bundled example: `cp -R docs/features/extensions/example-provider ~/.claudebar/extensions/`. Its scripts print fixed sample data, so it works without an account.

## How a script is run

For each section, on every refresh:

- ClaudeBar runs `command` with `/bin/sh -c`, from the extension's folder. A relative `command` is taken relative to that folder. It must be the path of an executable file (with a `#!` line and `chmod +x`).
- Every config value, or its `default`, is passed as an environment variable: `CLAUDEBAR_` plus the field `id` in upper snake case. `apiKey` becomes `CLAUDEBAR_API_KEY`, and `base-url` becomes `CLAUDEBAR_BASE_URL`.
- The script must exit `0` and print **one JSON object**. Which key it must contain depends on the section `type`: `quotas`, `costUsage`, `dailyUsage`, `metrics` or `status`. See [manifest.md](manifest.md#what-a-script-must-print).
- It's stopped after `timeout` seconds (default 10).

Sections run in parallel. The provider shows everything the successful sections returned. A section that fails is left out, and the provider shows an error only when every section fails.

## Gotchas

- **Changed the manifest? Restart ClaudeBar.** Script changes are picked up on the next refresh, but manifests are read only at launch.
- **An invalid manifest is skipped silently.** If the provider doesn't appear, check the JSON parses (`jq . manifest.json`) and that `id`, `name`, `version` and at least one section are present, and every section `type` is one of the six listed in [manifest.md](manifest.md#sections). At launch the log (**Settings → Logs → Open Log File**) records `Loaded N extension provider(s)` with their names.
- **`command` is a path, not a command line.** `./probe.sh` and `/usr/local/bin/my-probe` work. `python3 probe.py` and `./probe.sh --flag` don't: ClaudeBar checks that a file with that exact name exists, and skips the refresh when no section's file does. Use a wrapper script with a `#!` line instead.
- **No spaces in the path.** The command path isn't quoted, so a folder name like `My Provider` breaks it. Use `my-provider`.
- **Print only JSON, and print it all at once.** The script's stderr is captured together with stdout, so progress output (for example `curl` without `-s`) makes the JSON invalid. And once the script has printed something, ClaudeBar stops reading if it then prints nothing for 3 seconds. Build the result first, then print it.
- **`probe.interval` is ignored.** Every section runs on each refresh, whatever its `interval` says.
- **`statusBanner` shows nothing yet.** Its output is checked for errors and then dropped. Use a `metricsRow` card or a `healthCheck` section to show status.
- **Daily usage cards** appear only with **Settings → General → Daily Usage Cards** on.
- **Metric labels must be unique** within a provider. Cards are told apart by `label`, so two metrics with the same label display wrongly.
- **Secrets aren't in the Keychain yet.** `secret` fields are stored in ClaudeBar's app preferences (UserDefaults), not in `settings.json`, and while a script runs its values are visible to your other processes through `ps`. Other fields go in `~/.claudebar/settings.json` under `extensions.<id>`.
- **Scripts run as you**, with your permissions. Only install extensions whose scripts you've read.
- **Debug outside the app.** Run the script by hand with the same variables, for example `CLAUDEBAR_API_KEY=… ./probe.sh | jq .`. ClaudeBar doesn't show why a section failed.

## See also

- [manifest.md](manifest.md): every manifest field, config field type and output format
- [design.md](design.md): how extensions are loaded and run, for contributors
