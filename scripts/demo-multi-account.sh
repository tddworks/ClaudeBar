#!/bin/bash
# Runs a Debug ClaudeBar against a throwaway home with "Acme", a demo provider
# with three accounts, so the multi-account screens can be checked by hand:
# the popover tab, the account chips and the warning line, the menu bar names,
# and Settings → Providers → Acme → Accounts (rename, reorder, pin, pause,
# remove, Add Account → Enter Login).
#
#   Personal      — healthy        (28% / 12% used)
#   Work — Acme   — warning        (70% / 59% used), pinned to the menu bar
#   Side Project  — its key fails  (HTTP 401), shown greyed with Re-auth
#
# Your real ~/.claudebar, Keychain and CLIs are never touched: the app runs
# with CFFIXED_USER_HOME pointing at the demo home, built-in providers off.
#
# Usage: scripts/demo-multi-account.sh [path/to/ClaudeBar.app]
#        (defaults to the newest Debug build in DerivedData)

set -euo pipefail

APP="${1:-$(ls -td ~/Library/Developer/Xcode/DerivedData/ClaudeBar-*/Build/Products/Debug/ClaudeBar.app 2>/dev/null | head -1)}"
DEMO_HOME="${DEMO_HOME:-${TMPDIR:-/tmp}/claudebar-demo}"
PORT="${DEMO_PORT:-47813}"

if [[ ! -x "$APP/Contents/MacOS/ClaudeBar" ]]; then
    echo "No Debug ClaudeBar.app found. Build the ClaudeBar scheme (Debug) or pass its path." >&2
    exit 1
fi

if [[ "$(cd "$(dirname "$DEMO_HOME")" 2>/dev/null && pwd)/$(basename "$DEMO_HOME")" == "$HOME" ]]; then
    echo "DEMO_HOME must not be your home folder." >&2
    exit 1
fi
if pgrep -xq ClaudeBar; then
    echo "Quit ClaudeBar first: two copies share one URL scheme and hook port." >&2
    exit 1
fi

rm -rf "$DEMO_HOME"
mkdir -p "$DEMO_HOME/.claudebar/providers"

python3 - "$DEMO_HOME" "$PORT" <<'PY'
import json, sys
home, port = sys.argv[1], sys.argv[2]
base = f"http://127.0.0.1:{port}/usage"
acme = {
    "profile": {"id": "custom-acme", "name": "Acme", "origin": "custom", "links": {},
                "look": {"symbol": "a.circle.fill"}},
    "dataSources": [{
        "kind": "api", "label": "API",
        "fetch": {"http": {"url": base}},
        "mapping": {"json": {"quotas": [
            {"kind": "session", "at": "$.s", "usedPercent": "used"},
            {"kind": "weekly", "at": "$.w", "usedPercent": "used"}]}}}],
    "defaultDataSource": "api",
    "accounts": {
        "form": [{"id": "login", "label": "Login"}],
        "patch": {"api": {"fetch": {"http": {"url": base + "?login={{account.login}}"}}}}},
}
json.dump(acme, open(f"{home}/.claudebar/providers/custom-acme.json", "w"), indent=2)

builtins = ("claude codex gemini antigravity zai copilot bedrock ampcode kimi kiro minimax "
            "deepseek cursor mistral opencode-go omp grok commandcode vercel-gateway alibaba").split()
providers = {id: {"isEnabled": False} for id in builtins}
providers["custom-acme"] = {
    "defaultAccountLabel": "Personal",
    "accounts": [
        {"accountId": "work", "label": "Work — Acme", "probeConfig": {"login": "work"}, "madeBy": "form"},
        {"accountId": "side", "label": "Side Project", "probeConfig": {"login": "side"}, "madeBy": "form"},
    ],
}
settings = {"providers": providers, "app": {
    "menuBarPercentageEnabled": True,
    "menuBarPercentageProviderId": "custom-acme",
    "menuBarAdditionalProviderIds": ["custom-acme.work"],
}}
json.dump(settings, open(f"{home}/.claudebar/settings.json", "w"), indent=2)
PY

# The demo API: each login answers its own numbers; "side" is refused.
python3 - "$PORT" <<'PY' &
import http.server, json, sys, urllib.parse
USED = {"": (28, 12), "work": (70, 59), "side": None}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        login = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("login", [""])[0]
        used = USED.get(login, (40, 20))
        if used is None:
            self.send_response(401); self.end_headers(); return
        body = json.dumps({"s": {"used": used[0]}, "w": {"used": used[1]}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT

echo "Demo home: $DEMO_HOME"
echo "Running $APP — quit ClaudeBar to end the demo."
CFFIXED_USER_HOME="$DEMO_HOME" HOME="$DEMO_HOME" "$APP/Contents/MacOS/ClaudeBar"
