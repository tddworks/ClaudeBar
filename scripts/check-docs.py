#!/usr/bin/env python3
"""Check ClaudeBar's docs against docs/documentation-design/README.md#enforcement.

Report-only by default (always exits 0). Pass --strict to exit 1 on any problem.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# Pages and assets under docs/ that are not docs (see the design's Layout section).
SKIP_PREFIXES = ("docs/mockups/", "docs/screenshots/", "docs/sponsors/")

LINE_BUDGETS = {"README.md": 150, "AGENTS.md": 100}
FEATURE_README_BUDGET = 200
AGENTS_CHAR_BUDGET = 12_000
CHANGELOG_BULLET_BUDGET = 300
DESCRIPTION_BUDGET = 250

CONTRIBUTORS_BLOCK = re.compile(
    r"<!-- ALL-CONTRIBUTORS-LIST:START.*?ALL-CONTRIBUTORS-LIST:END -->", re.S
)
CODE = re.compile(r"```.*?```|`[^`\n]*`", re.S)
LINK = re.compile(r"\]\(([^)\s]+)\)")
URL = re.compile(r"https?://\S+")

problems = []


def report(path, message):
    problems.append(f"{path}: {message}")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def markdown_files():
    files = ["README.md", "AGENTS.md", "CHANGELOG.md", "SPONSORS.md"]
    files += glob.glob("docs/**/*.md", recursive=True)
    files += glob.glob(".claude/skills/**/*.md", recursive=True)
    return sorted(
        f for f in set(files) if os.path.exists(f) and not f.startswith(SKIP_PREFIXES)
    )


def check_line_budgets():
    for path, budget in LINE_BUDGETS.items():
        if not os.path.exists(path):
            continue
        text = CONTRIBUTORS_BLOCK.sub("", read(path))
        lines = text.count("\n")
        if lines > budget:
            report(path, f"{lines} lines, budget {budget}")
    for path in glob.glob("docs/providers/*/README.md") + glob.glob("docs/features/*/README.md"):
        lines = read(path).count("\n")
        if lines > FEATURE_README_BUDGET:
            report(path, f"{lines} lines, budget {FEATURE_README_BUDGET}")
    if os.path.exists("AGENTS.md"):
        chars = len(read("AGENTS.md"))
        if chars > AGENTS_CHAR_BUDGET:
            report("AGENTS.md", f"{chars} chars, budget {AGENTS_CHAR_BUDGET}")


def check_descriptions():
    for path in glob.glob("docs/providers/*/README.md") + glob.glob("docs/features/*/README.md"):
        match = re.match(r"---\n(.*?)\n---\n", read(path), re.S)
        desc = match and re.search(r"^description:\s*(.+)$", match.group(1), re.M)
        if not desc:
            report(path, "missing frontmatter `description`")
        elif len(desc.group(1)) > DESCRIPTION_BUDGET:
            report(path, f"description is {len(desc.group(1))} chars, budget {DESCRIPTION_BUDGET}")


def check_changelog():
    if not os.path.exists("CHANGELOG.md"):
        return
    match = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## \[)", read("CHANGELOG.md"), re.S | re.M)
    if not match:
        report("CHANGELOG.md", "no [Unreleased] section")
        return
    for bullet in re.findall(r"^- .*(?:\n  .*)*", match.group(1), re.M):
        length = len(URL.sub("", bullet))
        if length > CHANGELOG_BULLET_BUDGET:
            report("CHANGELOG.md", f"[Unreleased] bullet is {length} chars, budget {CHANGELOG_BULLET_BUDGET}: {bullet[:60]}…")
        for target in LINK.findall(bullet):
            if not target.startswith(("http://", "https://")):
                report("CHANGELOG.md", f"[Unreleased] link must be absolute (Sparkle can't resolve it): {target}")


def check_links():
    for path in markdown_files():
        text = CODE.sub("", read(path))
        for target in LINK.findall(text):
            target = target.split("#", 1)[0]
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not os.path.exists(resolved):
                report(path, f"broken link: {target}")


def check_provider_coverage():
    for path in glob.glob("Sources/Domain/Provider/*/*Provider.swift"):
        match = re.search(r'public let id: String = "([^"]+)"', read(path))
        if match and not os.path.exists(f"docs/providers/{match.group(1)}/README.md"):
            report(path, f"no docs/providers/{match.group(1)}/README.md")


def check_generated():
    import subprocess

    result = subprocess.run([sys.executable, "scripts/gen-docs.py", "--check"], capture_output=True, text=True)
    if result.returncode != 0:
        report("docs/README.md", "stale; run scripts/gen-docs.py")


def main():
    strict = "--strict" in sys.argv
    check_line_budgets()
    check_descriptions()
    check_changelog()
    check_provider_coverage()
    check_generated()
    check_links()
    for problem in problems:
        print(problem)
    print(f"check-docs: {len(problems)} problem(s){'' if strict else ' (report-only)'}")
    return 1 if strict and problems else 0


if __name__ == "__main__":
    sys.exit(main())
