#!/bin/bash
# Production guardian/lease protocol with UUID-owned file state, without WindowServer writes.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
case "${1:-}" in
    "") ./scripts/build/build-app.sh ;;
    --skip-build) ;;
    *) echo "usage: $0 [--skip-build]" >&2; exit 2 ;;
esac
macpocket_native_report="$macpocket_root/.build/switcher-native-key-report.json"
rm -f "$macpocket_native_report"
.build/MacPocket.app/Contents/MacOS/MacPocket --audit-switcher-native-keys "$macpocket_native_report"
python3 - "$macpocket_native_report" <<'PY'
import json, pathlib, sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
failures = [key for key, value in report.get('checks', {}).items() if not value]
print(f"native keys: {len(report.get('checks', {}))} checks; failures: {failures}; {report.get('error', '')}")
assert report.get('productionLeaseAndPipeProtocol') is True
assert report.get('globalSettersExercised') is False
assert report.get('physicalKeyboardVerified') is False
raise SystemExit(0 if report.get('passed') and not failures else 1)
PY
python3 - "$macpocket_root" <<'PY'
import json, pathlib, select, subprocess, sys
root = pathlib.Path(sys.argv[1])
executable = str(root / '.build/MacPocket.app/Contents/MacOS/MacPocket')
checks = []
# The real backend is queried but never acquired: only Q or invalid input is sent.
for payload, expected in ((b'Q', 0), (b'?', 65)):
    process = subprocess.Popen([executable, '--switcher-native-key-guard'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert select.select([process.stdout], [], [], 3)[0], 'Native guardian readiness timed out'
        ready = process.stdout.readline().decode().strip()
        assert ready in ('R0', 'R1', 'R2', 'R3'), repr(ready)
        process.stdin.write(payload)
        process.stdin.flush()
        output, _ = process.communicate(timeout=3)
        checks.append({'input': payload.decode(), 'ready': ready, 'exit': process.returncode,
                       'reply': output.decode().strip(), 'acquireSent': False,
                       'passed': process.returncode == expected and (payload != b'Q' or output == b'Q\n')})
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
report = {'passed': all(check['passed'] for check in checks), 'checks': checks, 'systemMutationRequested': False}
(root / '.build/switcher-native-key-readonly-report.json').write_text(json.dumps(report, indent=2))
print(f"native keys, read only: {len(checks)} checks; passed: {report['passed']}")
assert report['passed']
PY
