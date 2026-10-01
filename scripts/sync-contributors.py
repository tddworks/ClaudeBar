#!/usr/bin/env python3
"""Render the landing-page contributor grid from .all-contributorsrc.

The all-contributors bot owns .all-contributorsrc and the README table. It can
only emit its own <table> markup, though, which doesn't fit the card grid in
docs/index.html — so this script renders that one surface instead, from the same
source of truth. It never edits .all-contributorsrc or the README.

Run after the bot's PR merges (CI does this automatically):

    python3 scripts/sync-contributors.py

Exits 0 when the file changes and 0 when it was already current; the printed
line tells CI which happened.
"""

import json
import os
import sys
from html import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RC = os.path.join(ROOT, ".all-contributorsrc")
INDEX = os.path.join(ROOT, "docs", "index.html")

START = "<!-- CONTRIBUTORS:START"
END = "<!-- CONTRIBUTORS:END -->"


def card(c):
    """One contributor card, matching the .contributor-card markup in index.html."""
    name = escape(c.get("name") or c["login"])
    profile = escape(c["profile"])
    avatar = escape(c["avatar_url"] + "&s=144")
    return (
        f'            <a href="{profile}" target="_blank" rel="noopener" class="contributor-card">\n'
        f'                <img src="{avatar}" width="72" height="72" '
        f'alt="{name}" loading="lazy" class="contributor-avatar"/>\n'
        f'                <span class="contributor-name">{name}</span>\n'
        f'            </a>\n'
    )


def main():
    with open(RC) as f:
        contributors = json.load(f)["contributors"]

    with open(INDEX) as f:
        html = f.read()

    try:
        i = html.index(START)
        j = html.index(END, i)
    except ValueError:
        sys.exit(f"markers {START} … {END} not found in {INDEX}")

    head = html[: html.index("-->", i) + 4]
    updated = head + "".join(card(c) for c in contributors) + "            " + html[j:]

    if updated == html:
        print("docs/index.html already up to date")
        return

    with open(INDEX, "w") as f:
        f.write(updated)
    print(f"docs/index.html synced ({len(contributors)} contributors)")


if __name__ == "__main__":
    main()
