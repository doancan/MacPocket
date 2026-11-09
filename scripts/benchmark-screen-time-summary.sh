#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
mkdir -p .build/screen-time-performance
xcrun swiftc -O -parse-as-library Sources/MacPocketCore/ScreenTime.swift Sources/MacPocketCore/UsagePeriodSummary.swift tools/screen-time-summary-benchmark.swift -o .build/screen-time-performance/benchmark
.build/screen-time-performance/benchmark "$macpocket_root/.build/screen-time-performance/benchmark.json"
