#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
macpocket_app="$macpocket_root/.build/disk-events-performance/DiskChangeAudit.app"
mkdir -p "$macpocket_app/Contents/MacOS"
xcrun swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos27.0" -parse-as-library Sources/MacPocketApp/DiskChangeObservation.swift tools/disk-change-smoke.swift -o "$macpocket_app/Contents/MacOS/DiskChangeAudit"
python3 - "$macpocket_app/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({'CFBundleIdentifier':'com.doancan.MacPocket.DiskChangeAudit','CFBundleExecutable':'DiskChangeAudit','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication'}, file)
PY
codesign --force --sign - "$macpocket_app"
macpocket_report="$macpocket_root/.build/disk-events-performance/native.json"
rm -f "$macpocket_report"
open -n -W "$macpocket_app" --args "$macpocket_report"
python3 - "$macpocket_report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
print(len(report['checks']), 'native checks; failed:', [k for k,v in report['checks'].items() if not v], report['error'])
sys.exit(0 if report['passed'] else 1)
PY
