#!/bin/bash
# Read-only hardware observations and owned loopback/fixture UI. No unplug, eject or network changes.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build-app.sh debug; fi
python3 - "$macpocket_root/.build/MacPocket.app" <<'PYDEBUG'
import plistlib,subprocess,sys
result=subprocess.run(['codesign','-d','--entitlements',':-',sys.argv[1]],capture_output=True,check=True)
if not plistlib.loads(result.stdout).get('com.apple.security.get-task-allow',False):
 raise SystemExit('Bu denetim Debug paketi gerektirir. --skip-build olmadan yeniden çalıştır.')
PYDEBUG
for macpocket_audit_language in tr en; do
    macpocket_audit_directory="$macpocket_root/.build/cable-impact/ui-$macpocket_audit_language"
    mkdir -p "$macpocket_audit_directory"
    rm -f "$macpocket_audit_directory/report.json"
    macpocket_audit_options=(-NSQuitAlwaysKeepsWindows NO)
    if [ "$macpocket_audit_language" = en ]; then macpocket_audit_options+=(--audit-dark); fi
    open -n -g -W "$macpocket_root/.build/MacPocket.app" --args --audit-cable-impact "$macpocket_audit_directory" \
        -AppleLanguages "($macpocket_audit_language)" "${macpocket_audit_options[@]}"
    python3 - "$macpocket_audit_directory/report.json" "$macpocket_audit_language" <<'PY'
import json,pathlib,sys
report=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(sys.argv[2], 'checks:', len(report['checks']), 'failed:', [key for key,value in report['checks'].items() if not value], report['error'])
assert report['details'].get('language')==sys.argv[2], 'Wrong runtime language'
raise SystemExit(0 if report['passed'] else 1)
PY
done
