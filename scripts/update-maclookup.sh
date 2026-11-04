#!/bin/bash
# Bundle the MACLookup JSON snapshot for offline manufacturer lookup.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
macpocket_work="$(mktemp -d)"
trap 'rm -rf "$macpocket_work"' EXIT
curl -fsSL --retry 2 --max-time 120 \
    https://maclookup.app/downloads/json-database/get-db -o "$macpocket_work/maclookup.json"
/usr/bin/python3 -I - "$macpocket_work/maclookup.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    rows = json.load(handle)
if not isinstance(rows, list) or len(rows) < 50_000:
    raise SystemExit("Unexpected MACLookup database payload")
for row in rows:
    if not all(isinstance(row.get(key), str) for key in ("macPrefix", "vendorName", "blockType")) or not isinstance(row.get("private"), bool):
        raise SystemExit("Unexpected MACLookup record format")
print(f"MACLookup: {len(rows)} records")
PY
cat > "$macpocket_work/compress.swift" <<'SWIFT'
import Foundation
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
try ((input as NSData).compressed(using: .lzfse) as Data).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
SWIFT
swift "$macpocket_work/compress.swift" "$macpocket_work/maclookup.json" "$macpocket_root/Resources/maclookup.json.lzfse"
ls -lh "$macpocket_root/Resources/maclookup.json.lzfse"
