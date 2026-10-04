#!/bin/bash
# Replays real `claude /usage` captures through the shipping readiness rule.
#
#   scripts/replay-claude-usage-captures.sh                      # committed corpus
#   scripts/replay-claude-usage-captures.sh --corpus <dir>      # your own captures
#   scripts/replay-claude-usage-captures.sh --extract <ClaudeBar.log> --out <dir> [--all]
#
# Compiles the real `CLICompletionRule` together with the driver, so what is
# measured is the shipping matcher and not a copy of it. Exits non-zero if a
# settled capture is not recognised as ready, or a boot capture is.
#
# Needs a Swift toolchain (swiftc); the committed corpus is in
# scripts/claude-usage-captures/ and carries no credentials or personal data.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"
rule="$repo/Sources/Infrastructure/Shared/CLICompletionRule.swift"
driver="$here/replay-claude-usage-captures.swift"

for file in "$rule" "$driver"; do
    if [[ ! -f "$file" ]]; then
        echo "missing $file" >&2
        exit 2
    fi
done

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found — install the Swift toolchain (xcode-select --install)" >&2
    exit 2
fi

bin="$(mktemp -d)/replay"
trap 'rm -rf "$(dirname "$bin")"' EXIT

swiftc -O -parse-as-library -o "$bin" "$rule" "$driver"
exec "$bin" "$@"
