#!/usr/bin/env python3
"""
ClaudeBar Touch Bar Status Helper
Reads ~/.claudebar/status.json and formats output for BetterTouchTool (BTT), MTMR, and CLI,
with full support for real provider icons.

Usage:
    python3 scripts/touchbar_status.py --btt       # BetterTouchTool JSON format (with real icon image)
    python3 scripts/touchbar_status.py --mtmr      # MTMR plain text with status emoji
    python3 scripts/touchbar_status.py --text      # Plain menu bar text
    python3 scripts/touchbar_status.py --json      # Raw status JSON
    python3 scripts/touchbar_status.py --refresh   # Trigger ClaudeBar refresh
    python3 scripts/touchbar_status.py --open      # Open ClaudeBar dropdown
    python3 scripts/touchbar_status.py --settings  # Open ClaudeBar Settings
"""

import sys
import os
import json
import subprocess
import urllib.request

STATUS_FILE = os.path.expanduser("~/.claudebar/status.json")
ICONS_USER_DIR = os.path.expanduser("~/.claudebar/icons")
ICONS_SCRIPT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")

# Fallback emoji if real PNG icon is not found
FALLBACK_EMOJIS = {
    "claude": "🤖",
    "gemini": "✨",
    "codex": "💻",
    "copilot": "🐙",
    "antigravity": "⚡",
    "bedrock": "☁️",
    "deepseek": "🐋",
    "grok": "🚀",
    "kimi": "🌙",
    "cursor": "🎯",
    "zai": "⚡",
    "minimax": "🔥",
    "mistral": "🌪️",
    "opencode": "🌐",
    "omp": "🥧",
    "vercel": "▲",
    "alibaba": "☁️",
    "ampcode": "⚡",
    "kiro": "⚡",
}

STATUS_COLORS = {
    # Format: R,G,B,A (0-255)
    "healthy": "34,139,34,255",       # Forest green
    "warning": "204,136,0,255",       # Dark amber / gold
    "critical": "198,40,40,255",      # Crimson red
    "depleted": "150,20,20,255",      # Deep dark red
    "unknown": "50,50,50,255",        # Slate dark gray
}

STATUS_EMOJIS = {
    "healthy": "🟢",
    "warning": "🟡",
    "critical": "🔴",
    "depleted": "⛔",
    "unknown": "⚪",
}


def load_status():
    if not os.path.exists(STATUS_FILE):
        return None
    try:
        with open(STATUS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def get_icon_path(provider_id):
    """Finds the real PNG icon path for the given provider."""
    pid = (provider_id or "").lower()
    
    # 1. Check ~/.claudebar/icons/<pid>.png
    user_icon = os.path.join(ICONS_USER_DIR, f"{pid}.png")
    if os.path.isfile(user_icon):
        return user_icon
        
    # 2. Check scripts/icons/<pid>.png
    script_icon = os.path.join(ICONS_SCRIPT_DIR, f"{pid}.png")
    if os.path.isfile(script_icon):
        return script_icon
        
    return None


def get_fallback_emoji(provider_id):
    return FALLBACK_EMOJIS.get((provider_id or "").lower(), "🤖")


def format_btt(data):
    """Outputs JSON payload expected by BetterTouchTool Shell Script Widget."""
    if not data:
        fallback_icon = os.path.join(ICONS_USER_DIR, "claude.png")
        payload = {
            "text": "ClaudeBar: Offline",
            "font_color": "200,200,200,255",
            "background_color": "40,40,40,255"
        }
        if os.path.isfile(fallback_icon):
            payload["icon_path"] = fallback_icon
        else:
            payload["text"] = "🤖 ClaudeBar: Offline"
        return json.dumps(payload, ensure_ascii=False)

    if not data.get("enabled", True):
        # Disabled in ClaudeBar Settings: hide the widget
        return json.dumps({
            "text": "",
            "background_color": "0,0,0,0",
            "font_color": "0,0,0,0"
        })

    status = data.get("status", "unknown").lower()
    menu_text = data.get("menuBarText", "").strip()
    provider_id = data.get("selectedProviderId", "")
    provider_name = data.get("selectedProviderName", "ClaudeBar")
    
    icon_path = get_icon_path(provider_id)
    
    if icon_path:
        # Real icon image will be drawn by BetterTouchTool
        if provider_name.lower() in menu_text.lower():
            display_text = menu_text
        elif menu_text:
            display_text = f"{provider_name}: {menu_text}"
        else:
            display_text = provider_name
    else:
        # Fallback to emoji if PNG not found
        emoji = get_fallback_emoji(provider_id)
        if provider_name.lower() in menu_text.lower():
            display_text = f"{emoji} {menu_text}"
        elif menu_text:
            display_text = f"{emoji} {provider_name}: {menu_text}"
        else:
            display_text = f"{emoji} {provider_name}"

    bg_color = STATUS_COLORS.get(status, STATUS_COLORS["unknown"])

    payload = {
        "text": display_text,
        "font_color": "255,255,255,255",
        "background_color": bg_color,
    }
    
    if icon_path:
        payload["icon_path"] = icon_path

    return json.dumps(payload, ensure_ascii=False)


def format_mtmr(data):
    """Outputs plain text with emoji for MTMR (My TouchBar. My Rules.)."""
    if not data:
        return "⚪ ClaudeBar: Offline"

    if not data.get("enabled", True):
        return ""

    status = data.get("status", "unknown").lower()
    menu_text = data.get("menuBarText", "").strip()
    provider_id = data.get("selectedProviderId", "")
    provider_name = data.get("selectedProviderName", "ClaudeBar")
    emoji = get_fallback_emoji(provider_id)
    status_emoji = STATUS_EMOJIS.get(status, "⚪")

    if provider_name.lower() in menu_text.lower():
        return f"{status_emoji} {emoji} {menu_text}"
    elif menu_text:
        return f"{status_emoji} {emoji} {provider_name}: {menu_text}"
    else:
        return f"{status_emoji} {emoji} {provider_name}"


def format_text(data):
    """Outputs plain text."""
    if not data:
        return "ClaudeBar: Offline"
    return data.get("menuBarText", "ClaudeBar")


def trigger_url(scheme_url):
    try:
        subprocess.run(["open", scheme_url], check=True)
    except Exception as e:
        sys.stderr.write(f"Error opening {scheme_url}: {e}\n")


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "--btt"

    if arg in ("-h", "--help"):
        print(__doc__.strip())
        return
    elif arg == "--refresh":
        trigger_url("claudebar://refresh")
        return
    elif arg == "--open":
        trigger_url("claudebar://open")
        return
    elif arg == "--settings":
        trigger_url("claudebar://settings")
        return

    data = load_status()

    if arg == "--btt":
        print(format_btt(data))
    elif arg == "--mtmr":
        print(format_mtmr(data))
    elif arg == "--json":
        print(json.dumps(data, indent=2, ensure_ascii=False) if data else "{}")
    elif arg == "--text":
        print(format_text(data))
    elif arg == "--icon":
        pid = sys.argv[2] if len(sys.argv) > 2 else (data.get("selectedProviderId") if data else "claude")
        icon = get_icon_path(pid)
        print(icon or "")
    else:
        print(format_btt(data))


if __name__ == "__main__":
    main()
