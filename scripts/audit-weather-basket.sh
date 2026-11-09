#!/bin/bash
# Uses isolated settings/Keychain fixtures and public anonymous weather requests only.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build-app.sh debug; fi
python3 - "$macpocket_root/.build/MacPocket.app" <<'PYDEBUG'
import plistlib,subprocess,sys
r=subprocess.run(['codesign','-d','--entitlements',':-',sys.argv[1]],check=True,capture_output=True)
if not plistlib.loads(r.stdout).get('com.apple.security.get-task-allow'):raise SystemExit('Debug paket gerekir; --skip-build olmadan çalıştır.')
PYDEBUG
for macpocket_language in tr en; do
    macpocket_directory="$macpocket_root/.build/weather-basket/ui-$macpocket_language"
    mkdir -p "$macpocket_directory"
    rm -f "$macpocket_directory/report.json"
    macpocket_options=(-NSQuitAlwaysKeepsWindows NO)
    if [ "$macpocket_language" = en ]; then macpocket_options+=(--audit-dark); fi
    # The native accessibility actions require an active host window.
    open -n -W "$macpocket_root/.build/MacPocket.app" --args --audit-weather-basket "$macpocket_directory" -AppleLanguages "($macpocket_language)" "${macpocket_options[@]}"
    python3 - "$macpocket_directory/report.json" "$macpocket_language" <<'PYREPORT'
import json,pathlib,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(sys.argv[2], len(r['checks']), 'checks; failed:',[k for k,v in r['checks'].items() if not v],r['error'])
assert r['language']==sys.argv[2]
raise SystemExit(0 if r['passed'] else 1)
PYREPORT
done
