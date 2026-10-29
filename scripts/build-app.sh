#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
macpocket_configuration="${1:-debug}"
case "$macpocket_configuration" in debug|release) ;; *) echo "debug veya release seçin." >&2; exit 1 ;; esac
swift build -c "$macpocket_configuration" --product MacPocket
macpocket_binary_dir="$(swift build -c "$macpocket_configuration" --show-bin-path)"
macpocket_app_dir="$macpocket_root/.build/MacPocket.app"
mkdir -p "$macpocket_app_dir/Contents/MacOS"
mkdir -p "$macpocket_app_dir/Contents/Resources"
install -m 755 "$macpocket_binary_dir/MacPocket" "$macpocket_app_dir/Contents/MacOS/MacPocket"
install -m 644 Resources/Info.plist "$macpocket_app_dir/Contents/Info.plist"
install -m 644 Resources/AppIcon.icns "$macpocket_app_dir/Contents/Resources/AppIcon.icns"
if [ "$macpocket_configuration" = debug ]; then
    codesign --force --sign - --entitlements Resources/MacPocket.entitlements "$macpocket_app_dir"
else
    codesign --force --sign - "$macpocket_app_dir"
fi
codesign --verify --strict "$macpocket_app_dir"
echo "$macpocket_app_dir"
