#!/bin/bash
# Extract release notes for a specific version from CHANGELOG.md.
# Falls back to [Unreleased] section if [VERSION] is not found yet.
# Usage: ./scripts/extract-changelog.sh <version> [changelog_file]
# Example: ./scripts/extract-changelog.sh 0.5.1
#
# Output: markdown for the GitHub Release and Sparkle's update dialog (appcast.xml)

set -e

VERSION="${1#v}"
CHANGELOG_FILE="${2:-CHANGELOG.md}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [changelog_file]" >&2
    exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "Error: $CHANGELOG_FILE not found" >&2
    exit 1
fi

# 1. Try versioned section: ## [VERSION]
# A section ends at the next release, the `---` separator, the "Older
# releases" line or the reference links — never at an in-section `## `
# heading such as GitHub's "## New Contributors".
NOTES=$(awk -v version="$VERSION" '
    /^## \[/ {
        if (printing) { exit }
        if (index($0, "[" version "]") > 0) { printing=1; next }
    }
    printing && (/^---$/ || /^## Older releases/ || /^\[[^]]+\]: /) { exit }
    printing { print }
' "$CHANGELOG_FILE")

# 2. Fall back to [Unreleased] section
if [ -z "$NOTES" ]; then
    NOTES=$(awk '
        /^## \[Unreleased\]/ { printing=1; next }
        /^## \[/             { if (printing) exit }
        /^---$/              { if (printing) exit }
        printing             { print }
    ' "$CHANGELOG_FILE")
fi

if [ -z "$NOTES" ]; then
    echo "Error: No notes found for v$VERSION or [Unreleased] in $CHANGELOG_FILE" >&2
    exit 1
fi

# Collapse multiple blank lines; trim trailing blank lines
echo "$NOTES" \
  | sed '/^$/N;/^\n$/d' \
  | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
