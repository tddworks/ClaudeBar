#!/usr/bin/env bash
# Builds ClaudeBarKit, the Kotlin SDK the app links (docs/architecture/MODULAR_DESIGN.md).
# Run before `tuist generate`; needs JDK 21. Writes
#   ClaudeBarKit/build/XCFrameworks/release/ClaudeBarKit.xcframework
set -euo pipefail
cd "$(dirname "$0")/../ClaudeBarKit"
./gradlew assembleClaudeBarKitReleaseXCFramework --console=plain -q "$@"
echo "ClaudeBarKit.xcframework → $(pwd)/build/XCFrameworks/release/ClaudeBarKit.xcframework"
