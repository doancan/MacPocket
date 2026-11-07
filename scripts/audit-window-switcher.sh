#!/bin/bash
# Runs only owned fixture images and local AppKit input in an isolated debug bundle.
# Does not request TCC permissions, register global shortcuts, or mutate other applications' windows.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build-app.sh; fi
macpocket_audit_subset=""
case "${2:-}" in
    "") ;;
    --only-settings|--only-navigation|--only-gesture|--only-badges|--only-transfer|--only-cli|--only-hold) macpocket_audit_subset="$2" ;;
    *) echo "Bilinmeyen denetim seçeneği: $2" >&2; exit 2 ;;
esac
macpocket_audit_root="$macpocket_root/.build/switcher-audit"
mkdir -p "$macpocket_audit_root"
macpocket_file_controller=""
if [ "$macpocket_audit_subset" = "--only-transfer" ] || [ -z "$macpocket_audit_subset" ]; then
    rm -f "$macpocket_audit_root/file-controller-ready.json" "$macpocket_audit_root/file-controller.stop" "$macpocket_audit_root/file-controller-progress.json" "$macpocket_audit_root/file-controller-report.json" "$macpocket_audit_root/file-controller-last-pending.json"
    open -n -W "$macpocket_root/.build/MacPocket.app" --args --audit-transfer-file-controller "$macpocket_audit_root" &
    macpocket_file_controller=$!
    trap 'touch "$macpocket_audit_root/file-controller.stop"' EXIT
    python3 - "$macpocket_audit_root/file-controller-ready.json" <<'PY'
import json,pathlib,sys,time
path=pathlib.Path(sys.argv[1])
deadline=time.monotonic()+8
while not path.exists() and time.monotonic()<deadline: time.sleep(.05)
assert path.exists() and json.loads(path.read_text()).get('accessibility'), 'Production identity AX grant is unavailable'
PY
fi
for macpocket_audit_language in tr en; do
    macpocket_audit_app="$macpocket_audit_root/MacPocket-$macpocket_audit_language.SwitcherAudit.app"
    ditto .build/MacPocket.app "$macpocket_audit_app"
    python3 - "$macpocket_audit_app/Contents/Info.plist" "$macpocket_audit_language" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
info['CFBundleIdentifier'] = f'com.doancan.MacPocket.Audit.{sys.argv[2]}.SwitcherAudit'
info['CFBundleName'] = 'MacPocket Switcher Audit'
with open(sys.argv[1], 'wb') as target:
    plistlib.dump(info, target)
PY
    codesign --force --sign - "$macpocket_audit_app"
    mkdir -p "$macpocket_audit_root/$macpocket_audit_language"
    rm -f "$macpocket_audit_root/$macpocket_audit_language/report.json"
    macpocket_audit_options=(--audit-switcher "$macpocket_audit_root/$macpocket_audit_language/report.json")
    if [ -n "$macpocket_audit_subset" ]; then macpocket_audit_options+=("$macpocket_audit_subset"); fi
    open -n -W "$macpocket_audit_app" --args -MacPocket.languageConfigured YES \
        -AppleLanguages "($macpocket_audit_language)" -NSQuitAlwaysKeepsWindows NO \
        "${macpocket_audit_options[@]}"
done
if [ -n "$macpocket_file_controller" ]; then
    touch "$macpocket_audit_root/file-controller.stop"
    wait "$macpocket_file_controller"
fi
python3 - "$macpocket_audit_root" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
passed = True
for language in ('tr', 'en'):
    report = json.loads((root / language / 'report.json').read_text())
    failures = [key for key, value in report.get('checks', {}).items() if not value]
    print(f"{language}: {len(report.get('checks', {}))} checks; failures: {failures}; {report.get('error', '')}")
    passed &= report.get('passed', False)
raise SystemExit(0 if passed else 1)
PY
