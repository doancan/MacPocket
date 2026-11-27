#!/bin/bash
# Uses an isolated Debug bundle and owned status items. Never activates the network filter.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build/build-app.sh debug; fi
macpocket_audit_root="$macpocket_root/.build/product-expansion-audit"
macpocket_fixture="$macpocket_audit_root/MenuBarFixture.app"
mkdir -p "$macpocket_fixture/Contents/MacOS"
swiftc -parse-as-library scripts/audit/fixtures/MenuBarFixture.swift -o "$macpocket_fixture/Contents/MacOS/MenuBarFixture"
python3 - "$macpocket_fixture/Contents/Info.plist" <<'PYINFO'
import pathlib,plistlib,sys
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.doancan.MacPocket.MenuFixture','CFBundleExecutable':'MenuBarFixture','CFBundleName':'MacPocket Menu Fixture','CFBundlePackageType':'APPL','LSUIElement':True,'NSPrincipalClass':'NSApplication'}))
PYINFO
codesign --force --sign - "$macpocket_fixture"
rm -f "$macpocket_audit_root/report.json"
open -n -g -W "$macpocket_root/.build/MacPocket.app" --args --audit-product-expansion-native "$macpocket_audit_root/report.json" "$macpocket_fixture"
python3 - "$macpocket_audit_root/report.json" <<'PYREPORT'
import json,pathlib,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text())
print('Checks:',len(r['checks']),'failures:',[k for k,v in r['checks'].items() if not v],r.get('error'))
raise SystemExit(0 if r['passed'] else 1)
PYREPORT
