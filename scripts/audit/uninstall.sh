#!/bin/bash
# Stops/moves only freshly copied fixtures. Never uninstalls or closes a user application.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build/build-app.sh debug; fi
python3 - "$macpocket_root/.build/MacPocket.app" <<'PYDEBUG'
import plistlib,subprocess,sys
r=subprocess.run(['codesign','-d','--entitlements',':-',sys.argv[1]],check=True,capture_output=True)
if not plistlib.loads(r.stdout).get('com.apple.security.get-task-allow'):raise SystemExit('error: debug build required; run without --skip-build')
PYDEBUG
macpocket_fixture="$macpocket_root/.build/uninstall-improvements/UninstallFixture.app"
mkdir -p "$macpocket_fixture/Contents/MacOS"
swiftc -parse-as-library scripts/audit/fixtures/UninstallFixture.swift -o "$macpocket_fixture/Contents/MacOS/UninstallFixture"
xcrun clang scripts/audit/fixtures/UninstallWorker.c -o "$macpocket_fixture/Contents/MacOS/uninstall-worker"
python3 - "$macpocket_fixture/Contents/Info.plist" <<'PYINFO'
import pathlib,plistlib,sys
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.doancan.MacPocket.UninstallFixture','CFBundleExecutable':'UninstallFixture','CFBundleName':'Owned Uninstall Fixture','CFBundlePackageType':'APPL','LSUIElement':True,'NSPrincipalClass':'NSApplication'}))
PYINFO
codesign --force --sign - "$macpocket_fixture/Contents/MacOS/uninstall-worker"
codesign --force --sign - "$macpocket_fixture"
for macpocket_language in tr en; do
    macpocket_directory="$macpocket_root/.build/uninstall-improvements/ui-$macpocket_language"
    mkdir -p "$macpocket_directory"
    rm -f "$macpocket_directory/report.json"
    macpocket_options=(-NSQuitAlwaysKeepsWindows NO)
    if [ "$macpocket_language" = en ]; then macpocket_options+=(--audit-dark); fi
    open -n -g -W "$macpocket_root/.build/MacPocket.app" --args --audit-uninstall "$macpocket_directory" "$macpocket_fixture" -AppleLanguages "($macpocket_language)" "${macpocket_options[@]}"
    python3 - "$macpocket_directory/report.json" "$macpocket_language" <<'PYREPORT'
import pathlib,json,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(sys.argv[2],len(r['checks']),'checks; failed:',[k for k,v in r['checks'].items() if not v],r['error'])
assert r['language']==sys.argv[2]
raise SystemExit(0 if r['passed'] else 1)
PYREPORT
done
