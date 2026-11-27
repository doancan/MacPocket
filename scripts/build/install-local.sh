#!/bin/bash
# Builds the app from the working tree and replaces the copy in ~/Applications, then relaunches it.
# The version in Resources/Info.plist is left alone; this is for trying changes before a release.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
macpocket_configuration="${1:-release}"
case "$macpocket_configuration" in debug|release) ;; *) echo "usage: install-local.sh [debug|release]" >&2; exit 1 ;; esac
macpocket_bundle_id="com.doancan.MacPocket"
macpocket_target_dir="$HOME/Applications"
macpocket_target="$macpocket_target_dir/MacPocket.app"
macpocket_staging="$macpocket_target_dir/.MacPocket.app.installing"

./scripts/build/build-app.sh "$macpocket_configuration"

# Quit only a running copy: "tell application id … to quit" would launch the app when it is not running.
if pgrep -x MacPocket >/dev/null; then
    echo "quitting running MacPocket..." >&2
    osascript -e "tell application id \"$macpocket_bundle_id\" to quit"
    for _ in $(seq 1 50); do
        pgrep -x MacPocket >/dev/null || break
        sleep 0.2
    done
    if pgrep -x MacPocket >/dev/null; then
        echo "error: MacPocket did not quit within 10s; install aborted. Quit it manually and retry." >&2
        exit 1
    fi
fi

mkdir -p "$macpocket_target_dir"
rm -rf "$macpocket_staging"
ditto "$macpocket_root/.build/MacPocket.app" "$macpocket_staging"
codesign --verify --strict "$macpocket_staging"
rm -rf "$macpocket_target"
mv "$macpocket_staging" "$macpocket_target"
open "$macpocket_target"
echo "installed and launched: $macpocket_target ($(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo '+dirty'))" >&2
