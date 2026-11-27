#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
mkdir -p .build/bundle-index-performance
xcrun swiftc -O -parse-as-library Sources/MacPocketCore/InstalledBundleIndex.swift scripts/bench/bundle-index-benchmark.swift -o .build/bundle-index-performance/benchmark
.build/bundle-index-performance/benchmark "$macpocket_root/.build/bundle-index-performance/benchmark.json"
