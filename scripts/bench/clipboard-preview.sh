#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
mkdir -p .build/clipboard-preview-performance
xcrun swiftc -O -parse-as-library Sources/MacPocketCore/ClipboardTextPreview.swift scripts/bench/clipboard-preview-benchmark.swift -o .build/clipboard-preview-performance/benchmark
.build/clipboard-preview-performance/benchmark "$macpocket_root/.build/clipboard-preview-performance/benchmark.json"
