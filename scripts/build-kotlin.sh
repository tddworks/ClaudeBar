#!/usr/bin/env bash
# Builds the Kotlin kernel the Quotas module links (docs/architecture/MODULAR_DESIGN.md §3.1).
# Run before `tuist generate`; needs JDK 21. Writes
#   Modules/Quotas/Kotlin/build/XCFrameworks/release/QuotaKernel.xcframework
set -euo pipefail
cd "$(dirname "$0")/../Modules/Quotas/Kotlin"
./gradlew assembleQuotaKernelReleaseXCFramework --console=plain -q "$@"
echo "QuotaKernel.xcframework → $(pwd)/build/XCFrameworks/release/QuotaKernel.xcframework"
