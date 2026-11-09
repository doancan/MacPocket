#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
mkdir -p .build/hardware-performance
xcrun swiftc -O -parse-as-library Sources/MacPocketCore/GPUSampler.swift tools/gpu-sampler-benchmark.swift -o .build/hardware-performance/gpu-benchmark
.build/hardware-performance/gpu-benchmark "$macpocket_root/.build/hardware-performance/gpu.json"
