#!/bin/bash
# Native popover handoffs; isolated fixture status items, no account/settings access.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build-app.sh debug; fi
python3 - "$macpocket_root/.build/MacPocket.app" <<'PY'
import plistlib, subprocess, sys
result = subprocess.run(['codesign', '-d', '--entitlements', ':-', sys.argv[1]], check=True, capture_output=True)
if not plistlib.loads(result.stdout).get('com.apple.security.get-task-allow'):
    raise SystemExit('Debug paket gerekir; --skip-build olmadan çalıştır.')
PY
macpocket_report="$macpocket_root/.build/status-popover/runtime.json"
mkdir -p "$(dirname "$macpocket_report")"
rm -f "$macpocket_report"
open -n -W "$macpocket_root/.build/MacPocket.app" --args -NSQuitAlwaysKeepsWindows NO --audit-status-popover "$macpocket_report"
python3 - "$macpocket_report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
failed = [name for name, passed in report['checks'].items() if not passed]
print(len(report['checks']), 'native checks; failed:', failed)
sys.exit(0 if report['passed'] else 1)
PY
