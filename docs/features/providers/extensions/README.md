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
2. **Settings → Providers → My Provider** shows the fields your manifest declares, like any provider's settings. Enter the API key there.
3. The provider appears in the popover like any other and refreshes with the rest (**Settings → Sync & Alerts** sets how often).

To try the bundled example: `cp -R docs/features/providers/extensions/example-provider ~/.claudebar/extensions/`. Its scripts print fixed sample data, so it works without an account.

## How a script is run

For each section, on every refresh:

- ClaudeBar runs `command` from the extension's folder. A relative `command` is taken relative to that folder. On the Mac it runs with `/bin/sh -c`, so it must be an executable file (with a `#!` line and `chmod +x`). On Windows it is run as the file itself, so it must be a `.cmd`, `.bat` or `.exe`; a `sh` script doesn't run there.
- Every config value, or its `default`, is passed as an environment variable: `CLAUDEBAR_` plus the field `id` in upper snake case. `apiKey` becomes `CLAUDEBAR_API_KEY`, and `base-url` becomes `CLAUDEBAR_BASE_URL`.
- The script must exit `0` and print **one JSON object** with `quotas` or `costUsage`. See [manifest.md](manifest.md#what-a-script-must-print).
- It's stopped after `timeout` seconds (default 10).

Sections run in parallel. The provider shows everything the successful sections returned. A section that fails is left out, and its error shows beside the rest (a down `healthCheck` reads *Couldn't connect*); the provider fails only when every section does.

## Gotchas

- **Changed the manifest? Restart ClaudeBar.** Script changes are picked up on the next refresh, but manifests are read only at launch.
- **An invalid manifest is skipped silently.** If the provider doesn't appear, check the JSON parses (`jq . manifest.json`) and that `id`, `name`, `version` and at least one section are present, and at least one section is a `quotaGrid`, `costUsage` or `healthCheck` ([manifest.md](manifest.md#sections)). The log (**Settings → Logs → Open Log File**) records `Skipping extension <folder>` with the reason.
- **`command` is a path, not a command line.** `./probe.sh` and `/usr/local/bin/my-probe` work. `python3 probe.py` and `./probe.sh --flag` don't: ClaudeBar checks that a file with that exact name exists, and skips the refresh when no section's file does. Use a wrapper script with a `#!` line instead.
- **Print only JSON, and print it all at once.** The script's stderr is captured together with stdout, so progress output (for example `curl` without `-s`) makes the JSON invalid. And once the script has printed something, ClaudeBar stops reading if it then prints nothing for 3 seconds. Build the result first, then print it.
- **`probe.interval` is ignored.** Every section runs on each refresh, whatever its `interval` says.
- **`dailyUsage`, `metricsRow` and `statusBanner` sections are no longer read** (since the release after 0.5.3). The log names each one skipped. For daily usage, write JSON-lines records that a provider's `usageHistory` reads, as every provider does.
- **Secrets are in the Keychain**, and reach the script as real environment variables, not on its command line. Saved values from before moved there once, on upgrade. Other fields are the provider's settings in `~/.claudebar/settings.json`.
- **Scripts run as you**, with your permissions. Only install extensions whose scripts you've read.
- **Debug outside the app.** Run the script by hand with the same variables, for example `CLAUDEBAR_API_KEY=… ./probe.sh | jq .`. ClaudeBar doesn't show why a section failed.

## See also

- [manifest.md](manifest.md): every manifest field, config field type and output format
- [design.md](design.md): how extensions are loaded and run, for contributors
