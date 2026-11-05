#!/bin/bash
# Exercises the actual transfer helper with a synthetic AppKit producer; no user clipboard or files.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
mkdir -p .build
swiftc -swift-version 6 -parse-as-library \
    Sources/MacPocketApp/ShelfPromiseTransfer.swift Tests/Integration/ShelfPromiseProbe.swift \
    -o .build/shelf-promise-probe
.build/shelf-promise-probe .build/shelf-promise-probe.json
python3 - <<'PY'
import json
with open('.build/shelf-promise-probe.json') as source:
    report = json.load(source)
assert report['passed'], {key: value for key, value in report['checks'].items() if not value}
print(f"Shelf promise transfer: {len(report['checks'])} checks passed")
PY
