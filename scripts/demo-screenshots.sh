#!/bin/bash
# Runs a Debug ClaudeBar against a throwaway home with sample data only, for
# the website's screenshots: no real account, email, username or usage.
#
#   Claude       — session, weekly and Sonnet quotas, plus 30 days of sample
#                  usage logs (cost, tokens, working time)
#   Codex        — session and weekly
#   Gemini       — Pro and Flash
#   Antigravity  — two models, one low
#   Copilot      — premium requests
#
# Each one is a custom provider wearing the built-in's name, icon and colours,
# fed by a local stub server, so nothing reaches a real CLI or API. The
# Leaderboard tab still reads the live public board: don't screenshot it.
# Your real ~/.claudebar, Keychain and CLIs are never touched.
#
# Usage: scripts/demo-screenshots.sh [path/to/ClaudeBar.app] [theme]
#        theme: light (default), dark, cli, christmas, pop, system
#        DEMO_SCENE=in-use  Claude gets a second login, "work" (a folder), and
#                           the plain one is named "personal" — In use's strip,
#                           setup and Settings section show. The shell lines
#                           go to the demo home's .zshrc, never yours.
#        DEMO_LOW=1         with in-use: "personal" is at 8%, "work" at 81%
#        DEMO_SCENE=sections  adds Oh My Pi, read by its own script: a Claude
#                           and a Kimi section, then today's usage from the
#                           same sample logs
#        DEMO_SCENE=sessions  hooks on in the demo home, and six made-up Claude
#                           Code sessions posted to the hook server: one needs
#                           you, one with agents, four done (three in one repo),
#                           titled by made-up transcripts in the demo home.
#                           Your own Claude Code sessions post to the same
#                           port and show up too: point them elsewhere while
#                           you shoot (printf 9 > ~/.claude/claudebar-hook-port)
#                           and write 19847 back after.
#        DEMO_TEXT_SIZE=extraLarge  the Popover Text Size (medium, large,
#                           extraLarge), set in the demo home's settings
#        DEMO_POPOVER_TITLE="Acme AI Desk"  the Popover Title, set the same way
#        (the app defaults to the newest Debug build in DerivedData)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="${1:-$(ls -td ~/Library/Developer/Xcode/DerivedData/ClaudeBar-*/Build/Products/Debug/ClaudeBar.app 2>/dev/null | head -1)}"
THEME="${2:-light}"
DEMO_HOME="${DEMO_HOME:-${TMPDIR:-/tmp}/claudebar-screenshots}"
PORT="${DEMO_PORT:-47814}"

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
mkdir -p "$DEMO_HOME/.claudebar/providers" "$DEMO_HOME/sample-logs"

python3 - "$DEMO_HOME" "$PORT" "$THEME" "${DEMO_SCENE:-}" "${DEMO_TEXT_SIZE:-medium}" "${DEMO_POPOVER_TITLE:-}" <<'PY'
import json, os, random, sys, uuid
from datetime import datetime, timedelta, timezone
home, port, theme, scene, text_size, popover_title = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
base = f"http://127.0.0.1:{port}"

def quota(kind, key, name=None):
    q = {"kind": kind, "at": f"$.{key}", "usedPercent": "used", "resetsAt": {"epochSeconds": "resets"}}
    if name: q["name"] = name
    return q

def look(builtin):
    # The built-in's own face: name, icon and colours.
    with open(f"Modules/Providers/Resources/Providers/{builtin}.json") as f:
        profile = json.load(f)["profile"]
    return profile["name"], profile["look"]

def provider(order, builtin, quotas, history=None, mapping=None):
    name, face = look(builtin)
    pid = f"custom-{order}-{builtin}"
    definition = {
        "profile": {"id": pid, "name": name, "origin": "custom", "links": {}, "look": face},
        "dataSources": [{"kind": "api", "label": "API",
                         "fetch": {"http": {"url": f"{base}/{builtin}"}},
                         "mapping": mapping or {"json": {"quotas": quotas}}}],
        "defaultDataSource": "api",
    }
    if history: definition["usageHistory"] = history
    if scene == "in-use" and builtin == "claude":
        # Logins that are folders, and the CLI's variable: what In use needs.
        definition["accounts"] = {
            "signIn": {"cli": "claude", "args": ["auth", "login"], "homeVariable": "CLAUDE_CONFIG_DIR"},
            "folder": {"savedAs": "configDirectory", "default": "~/.claude",
                       "accountId": {"field": "account", "savedAs": "loginEmail"}},
            "patch": {"api": {"fetch": {"http": {"url": f"{base}/{builtin}?login=work"}}}},
        }
    with open(f"{home}/.claudebar/providers/{pid}.json", "w") as f:
        json.dump(definition, f, indent=2)
    return pid

history = {
    "records": {"files": f"{home}/sample-logs/*.jsonl", "format": "jsonLines", "at": "$.at",
                "id": ["$.id"], "model": "$.model",
                "tokens": {"input": "$.input", "output": "$.output", "cacheRead": "$.cacheRead"},
                "cost": "$.cost"},
    "sessionGap": 1800,
}
ids = [
    provider("a", "claude", [quota("session", "session"), quota("weekly", "weekly"),
                             quota("model", "sonnet", "sonnet")], history),
    provider("b", "codex", [quota("session", "session"), quota("weekly", "weekly")]),
    provider("c", "gemini", [quota("model", "pro", "Pro"), quota("model", "flash", "Flash")]),
    provider("d", "antigravity", [quota("model", "claude", "Claude Sonnet"), quota("model", "gemini", "Gemini Pro")]),
    provider("e", "copilot", [quota("time", "premium", "Premium requests")]),
]
if scene == "sections":
    # omp's own script groups each upstream provider's limits into a section.
    ids.append(provider("f", "omp", [], history, {"script": {"file": "omp-usage.js"}}))

# 30 days of sample Claude usage: weekdays busier, a few sessions a day.
random.seed(7)
now = datetime.now(timezone.utc)
with open(f"{home}/sample-logs/sample.jsonl", "w") as log:
    for back in range(30, -1, -1):
        # Today's sessions end before now, so today's cards are never empty.
        day = now - timedelta(hours=7) if back == 0 else (now - timedelta(days=back)).replace(hour=9, minute=0, second=0, microsecond=0)
        busy = 0.35 if day.weekday() >= 5 else 1.0
        for session in range(random.randint(1, 3)):
            start = day + timedelta(hours=session * 3 + random.random())
            for step in range(int(random.randint(20, 45) * busy)):
                at = start + timedelta(minutes=step * random.uniform(2, 6))
                if at > now: break
                inp, out, cache = random.randint(4000, 20000), random.randint(1500, 12000), random.randint(100000, 450000)
                log.write(json.dumps({"at": at.isoformat().replace("+00:00", "Z"), "id": str(uuid.uuid4()),
                                      "model": "claude-sonnet-sample", "input": inp, "output": out,
                                      "cacheRead": cache, "cost": round(inp * 3e-6 + out * 15e-6 + cache * 0.3e-6, 4)}) + "\n")

builtins = ("claude codex gemini antigravity zai copilot bedrock ampcode kimi kiro minimax "
            "deepseek cursor mistral opencode-go omp grok commandcode vercel-gateway alibaba").split()
providers = {id: {"isEnabled": False} for id in builtins}
if scene == "in-use":
    os.makedirs(f"{home}/.claude-work", exist_ok=True)
    providers[ids[0]] = {"defaultAccountLabel": "personal", "accounts": [{
        "accountId": "work", "label": "work", "email": "work@example.com", "madeBy": "folder",
        "probeConfig": {"configDirectory": f"{home}/.claude-work", "loginEmail": "work@example.com"}}]}
settings = {"providers": providers, "app": {
    "themeMode": theme,
    # Chosen, so the Christmas theme stays outside its season.
    "userHasChosenTheme": True,
    "showDailyUsageCards": True,
    "popoverTextSize": text_size,
    "popoverTitle": popover_title,
    "menuBarPercentageEnabled": True,
    "menuBarPercentageProviderId": ids[0],
}}
if scene == "sessions":
    settings["hook"] = {"enabled": True}
with open(f"{home}/.claudebar/settings.json", "w") as f:
    json.dump(settings, f, indent=2)
PY

# Made-up Claude Code sessions, posted once the hook server listens.
if [[ "${DEMO_SCENE:-}" == "sessions" ]]; then
    (
        mkdir -p "$DEMO_HOME/transcripts"
        title() { echo "{\"type\":\"$2\",\"$3\":\"$4\"}" >> "$DEMO_HOME/transcripts/$1.jsonl"; }
        title blocked custom-title customTitle "Checkout tax rounding"
        title busy ai-title aiTitle "Show session titles on the card"
        title done-1 ai-title aiTitle "Paginate the product search"
        hook() { curl -s -o /dev/null -X POST "http://127.0.0.1:19847/hook" -H 'Content-Type: application/json' \
            -d "{\"session_id\":\"$1\",\"hook_event_name\":\"$2\",\"cwd\":\"/Users/demo/code/$3\",\"transcript_path\":\"$DEMO_HOME/transcripts/$1.jsonl\"}"; }
        for _ in $(seq 60); do curl -s -o /dev/null -X POST http://127.0.0.1:19847/hook && break; sleep 1; done
        hook done-1 Stop catalog; hook done-2 Stop claudebar; sleep 2
        hook done-3 Stop claudebar; hook done-4 Stop claudebar
        hook busy UserPromptSubmit claudebar; hook busy SubagentStart claudebar; hook busy SubagentStart claudebar
        hook busy TaskCompleted claudebar; hook busy TaskCompleted claudebar; hook busy TaskCompleted claudebar
        hook blocked UserPromptSubmit tinyshop; hook blocked Notification tinyshop
    ) &
fi

# The sample API: round numbers, resets a few hours and days out.
python3 - "$PORT" "${DEMO_LOW:-}" <<'PY' &
import http.server, json, sys, time
low = sys.argv[2] == "1"
H, D = 3600, 86400
def q(used, resets): return {"used": used, "resets": int(time.time()) + resets}
def limit(window, seconds, left, resets):
    # One limit as `omp usage --json` reports it.
    return {"scope": {"windowId": window}, "amount": {"remainingFraction": left},
            "window": {"id": window, "durationMs": seconds * 1000, "resetsAt": (int(time.time()) + resets) * 1000}}
ANSWERS = {
    "claude": {"session": q(92 if low else 15, 3 * H + 1500), "weekly": q(38, D + 19 * H), "sonnet": q(40, D + 19 * H)},
    "claude?login=work": {"session": q(19, 4 * H), "weekly": q(22, 3 * D), "sonnet": q(12, 3 * D)},
    "codex": {"session": q(22, 2 * H + 600), "weekly": q(47, 4 * D)},
    "gemini": {"pro": q(31, 14 * H), "flash": q(8, 14 * H)},
    "antigravity": {"claude": q(86, 2 * H), "gemini": q(35, 5 * H)},
    "copilot": {"premium": q(54, 18 * D)},
    "omp": {"reports": [
        {"provider": "anthropic", "limits": [limit("5h", 5 * H, 0.72, 3 * H), limit("7d", 7 * D, 0.55, 3 * D)]},
        {"provider": "kimi-code", "limits": [limit("5h", 5 * H, 0.90, 2 * H), limit("7d", 7 * D, 0.64, 4 * D)]},
    ]},
}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        answer = ANSWERS.get(self.path.strip("/")) or ANSWERS.get(self.path.strip("/").split("?")[0])
        if answer is None:
            self.send_response(404); self.end_headers(); return
        body = json.dumps(answer).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT

echo "Demo home: $DEMO_HOME (theme: $THEME)"
if [[ "${DEMO_SCENE:-}" == "sessions" && "$(cat "$HOME/.claude/claudebar-hook-port" 2>/dev/null || echo 19847)" == 19847 ]]; then
    echo "Your own Claude Code sessions will show up too; see DEMO_SCENE=sessions above."
fi
echo "Running $APP — quit ClaudeBar to end the demo."
CFFIXED_USER_HOME="$DEMO_HOME" HOME="$DEMO_HOME" "$APP/Contents/MacOS/ClaudeBar"
