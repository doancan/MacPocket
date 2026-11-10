#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
macpocket_output="${1:-$macpocket_root/.build/clipboard-search-performance}"
mkdir -p "$macpocket_output"
# Extract the unchanged shortcut key-name declaration required by ClipboardHistory.swift.
# Search/history implementations below are compiled directly from the working tree.
python3 - "$macpocket_root" "$macpocket_output" <<'PY'
import hashlib, json, pathlib, sys
root, output = map(pathlib.Path, sys.argv[1:])
source = (root / 'Sources/MacPocketCore/SwitcherConfiguration.swift').read_text()
keys = source.split('public enum SwitcherKeys {', 1)[1].split('\npublic enum SwitcherShortcutValidation', 1)[0]
(output / 'SwitcherKeys.swift').write_text('import Foundation\npublic enum SwitcherKeys {' + keys)
paths = ['Sources/MacPocketCore/' + name + '.swift' for name in
         ['ClipboardHistory', 'ClipboardTextPreview', 'ClipboardSearchIndex', 'SwitcherConfiguration']]
paths.append('tools/ClipboardSearchBenchmark.swift')
(output / 'source-sha256.json').write_text(json.dumps({name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in paths}, indent=2))
PY
swiftc -O -whole-module-optimization -parse-as-library \
    "$macpocket_root/Sources/MacPocketCore/ClipboardHistory.swift" \
    "$macpocket_root/Sources/MacPocketCore/ClipboardTextPreview.swift" \
    "$macpocket_root/Sources/MacPocketCore/ClipboardSearchIndex.swift" \
    "$macpocket_output/SwitcherKeys.swift" \
    "$macpocket_root/tools/ClipboardSearchBenchmark.swift" \
    -o "$macpocket_output/search-benchmark"
"$macpocket_output/search-benchmark" "$macpocket_output/search-report.json"
