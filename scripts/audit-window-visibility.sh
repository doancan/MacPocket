#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
macpocket_app="$macpocket_root/.build/background-performance/VisibilityAudit.app"
mkdir -p "$macpocket_app/Contents/MacOS"
xcrun swiftc -parse-as-library Sources/MacPocketApp/MainWindowVisibility.swift tools/window-visibility-smoke.swift -o "$macpocket_app/Contents/MacOS/VisibilityAudit"
python3 - "$macpocket_app/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({'CFBundleIdentifier':'com.doancan.MacPocket.VisibilityAudit','CFBundleExecutable':'VisibilityAudit','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication'}, file)
PY
codesign --force --sign - "$macpocket_app"
macpocket_report="$macpocket_root/.build/background-performance/visibility.json"
rm -f "$macpocket_report"
open -n -W "$macpocket_app" --args "$macpocket_report"
python3 - "$macpocket_report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
print(len(report['checks']), 'native checks; failed:', [k for k,v in report['checks'].items() if not v])
sys.exit(0 if report['passed'] else 1)
PY
