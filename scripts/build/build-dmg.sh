#!/bin/bash
# Usage: scripts/build/build-dmg.sh [signed-app] [output.dmg]
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
macpocket_app="${1:-$macpocket_root/.build/MacPocket.app}"
[[ -d "$macpocket_app/Contents" ]] || { echo "Application bundle not found: $macpocket_app" >&2; exit 1; }
macpocket_app="$(cd "$macpocket_app" && pwd)"
macpocket_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$macpocket_app/Contents/Info.plist")"
macpocket_dmg="${2:-$macpocket_root/.build/MacPocket-$macpocket_version-macOS-arm64.dmg}"
mkdir -p "$(dirname "$macpocket_dmg")"
macpocket_dmg="$(cd "$(dirname "$macpocket_dmg")" && pwd)/$(basename "$macpocket_dmg")"
[[ ! -e "$macpocket_dmg" ]] || { echo "Output already exists: $macpocket_dmg" >&2; exit 1; }
codesign --verify --strict --deep "$macpocket_app"

macpocket_tools="$macpocket_root/.build/dmg-tools"
macpocket_artwork="$(mktemp -d "$macpocket_root/.build/installer-artwork.XXXXXX")"
macpocket_mount="$macpocket_artwork/mounted"
macpocket_attached=false
macpocket_cleanup() {
    if "$macpocket_attached"; then hdiutil detach "$macpocket_mount" >/dev/null; fi
    rm -rf "$macpocket_artwork"
}
trap macpocket_cleanup EXIT
if ! "$macpocket_tools/bin/python" -c 'import dmgbuild' >/dev/null 2>&1; then
    python3 -m venv "$macpocket_tools"
fi
"$macpocket_tools/bin/python" -m pip install --disable-pip-version-check -r "$macpocket_root/scripts/build/dmg-requirements.txt"
xcrun swift "$macpocket_root/scripts/build/render-installer.swift" "$macpocket_root" "$macpocket_artwork" "$macpocket_app"
"$macpocket_tools/bin/python" -m dmgbuild -s "$macpocket_root/scripts/build/dmg-settings.py" \
    -D "app=$macpocket_app" -D "background=$macpocket_artwork/background.tiff" \
    "MacPocket $macpocket_version" "$macpocket_dmg"
hdiutil verify "$macpocket_dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$macpocket_mount" "$macpocket_dmg" >/dev/null
macpocket_attached=true
codesign --verify --strict --deep "$macpocket_mount/$(basename "$macpocket_app")"
[[ "$(readlink "$macpocket_mount/Applications")" == /Applications ]]
hdiutil detach "$macpocket_mount" >/dev/null
macpocket_attached=false
echo "$macpocket_dmg"
