#!/bin/bash
# Build a disposable, separate application for live window discovery/exit tests. Never installed or shipped.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
macpocket_fixture="$macpocket_root/.build/MacPocketDockFixture.app"
mkdir -p "$macpocket_fixture/Contents/MacOS"
swiftc -swift-version 6 -parse-as-library Tests/Integration/DockFixtureApp.swift \
    -o "$macpocket_fixture/Contents/MacOS/MacPocketDockFixture"
python3 - "$macpocket_fixture/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as target:
    plistlib.dump({'CFBundleIdentifier': 'com.doancan.MacPocket.DockFixture',
                  'CFBundleExecutable': 'MacPocketDockFixture', 'CFBundleName': 'MacPocket Dock Fixture',
                  'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication'}, target)
PY
codesign --force --sign - "$macpocket_fixture"
printf '%s\n' "$macpocket_fixture"
