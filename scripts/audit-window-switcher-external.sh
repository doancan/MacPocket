#!/bin/bash
# Acceptance uses the signed production identity and an owned, separate AppKit process.
# Default mode does not prompt for permissions or change user preferences/global hotkeys.
# Command+Tab/manual modes temporarily own real hotkeys and restore their initial state.
# --only-existing-focus explicitly exercises focus-only on visible iTerm2/VS Code windows.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
if [ "${1:-}" != "--skip-build" ]; then ./scripts/build-app.sh; fi
if [ "${2:-}" = "--only-existing-focus" ]; then
    macpocket_existing_run="$macpocket_root/.build/switcher-existing-focus-audit"
    mkdir -p "$macpocket_existing_run"
    rm -f "$macpocket_existing_run/report.json"
    open -n -W "$macpocket_root/.build/MacPocket.app" --args --audit-switcher-existing-focus "$macpocket_existing_run"
    python3 - "$macpocket_existing_run/report.json" <<'PY'
import json,pathlib,sys
report=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(f"existing focus: {len(report.get('checks',{}))} checks; failures: {[k for k,v in report.get('checks',{}).items() if not v]}; {report.get('error','')}")
raise SystemExit(0 if report.get('passed') else 1)
PY
    exit 0
fi
macpocket_audit_root="$macpocket_root/.build/switcher-external-audit"
macpocket_fixture="$macpocket_audit_root/WindowFixture.WindowFixtureAudit.app"
mkdir -p "$macpocket_fixture/Contents/MacOS" "$macpocket_fixture/Contents/Resources"
swiftc -parse-as-library -target "$(uname -m)-apple-macos27" scripts/fixtures/WindowSwitcherFixture.swift -o "$macpocket_fixture/Contents/MacOS/WindowFixture"
python3 - "$macpocket_fixture" <<'PY'
import pathlib,plistlib,sys,shutil
root=pathlib.Path(sys.argv[1])
info={'CFBundleIdentifier':'com.doancan.MacPocket.WindowFixtureAudit','CFBundleName':'MacPocket Window Fixture',
      'CFBundleExecutable':'WindowFixture','CFBundlePackageType':'APPL','NSHighResolutionCapable':True,
      'CFBundleDevelopmentRegion':'tr','CFBundleLocalizations':['tr','en'],'NSPrincipalClass':'NSApplication'}
(root/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
for language in ['en']:
    source=pathlib.Path(f'Resources/{language}.lproj')
    shutil.copytree(source,root/f'Contents/Resources/{language}.lproj',dirs_exist_ok=True)
PY
codesign --force --sign - "$macpocket_fixture"
macpocket_audit_option=""
case "${2:-}" in
    "") ;;
    --only-badge-focus|--only-cli|--only-command-tab-probe|--only-command-tab-reset|--only-performance|--only-carbon-hotkey|--only-system-command-tab|--only-manual-keyboard|--only-manual-keyboard-cancel) macpocket_audit_option="$2" ;;
    *) echo "Bilinmeyen denetim seçeneği: $2" >&2; exit 2 ;;
esac
mkdir -p "$macpocket_audit_root/run"
rm -f "$macpocket_audit_root/run/report.json"
macpocket_audit_args=(--audit-switcher-external "$macpocket_audit_root/run" "$macpocket_fixture")
if [ -n "$macpocket_audit_option" ]; then macpocket_audit_args+=("$macpocket_audit_option"); fi
open -n -W "$macpocket_root/.build/MacPocket.app" --args "${macpocket_audit_args[@]}"
python3 - "$macpocket_audit_root/run/report.json" <<'PY'
import json,pathlib,sys
report=json.loads(pathlib.Path(sys.argv[1]).read_text())
if report.get('expectedManualCancellation'):
    manual=report.get('systemCommandTab',{}).get('manualKeyboard',{})
    restored=report.get('checks',{})
    valid=manual.get('cancelled') is True and manual.get('physicalKeyboardVerified') is False and report.get('physicalHotkeysVerified') is False
    valid &= all(restored.get(key) is True for key in ['systemCommandTabAllOwnedGuardsExit','systemCommandTabOriginalNativeStateRestored','systemCommandTabSecureInputWasNotChanged','ownedExternalProcessExitsAndRestoresItsSpaces'])
    if report.get('systemCommandTab',{}).get('altTabWasRunning'): valid &= restored.get('systemCommandTabOriginalAltTabRestarts') is True
    print(f"manual cancellation cleanup: {valid}; physical input remains unverified")
    raise SystemExit(0 if valid else 1)
print(f"external: {len(report.get('checks',{}))} checks; failures: {[k for k,v in report.get('checks',{}).items() if not v]}; {report.get('error','')}")
raise SystemExit(0 if report.get('passed') else 1)
PY
