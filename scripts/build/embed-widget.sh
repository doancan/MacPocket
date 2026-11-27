#!/bin/bash
# Called by build-app.sh before the app is signed. Builds the Disk Röntgeni widget and embeds it as a WidgetKit
# extension. The widget is sandboxed and can only read the one file the app writes after a scan, so it needs no
# provisioning profile. A failure here only means the app ships without the widget.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
macpocket_widget_app="$1"
macpocket_widget_configuration="$2"
macpocket_widget_identity="$3"
swift build -c "$macpocket_widget_configuration" --product MacPocketWidget
macpocket_widget_bin="$(swift build -c "$macpocket_widget_configuration" --show-bin-path)"
macpocket_widget_bundle="$macpocket_widget_app/Contents/PlugIns/MacPocketWidget.appex"
rm -rf "$macpocket_widget_bundle"
mkdir -p "$macpocket_widget_bundle/Contents/MacOS" "$macpocket_widget_bundle/Contents/Resources"
install -m 755 "$macpocket_widget_bin/MacPocketWidget" "$macpocket_widget_bundle/Contents/MacOS/MacPocketWidget"
python3 - "$macpocket_widget_bundle/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
info = plistlib.loads(pathlib.Path('Resources/Widget/Info.plist').read_bytes())
host = plistlib.loads(pathlib.Path('Resources/Info.plist').read_bytes())
for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
    info[key] = host[key]
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
for macpocket_widget_lproj in Resources/Widget/*.lproj; do
    [ -d "$macpocket_widget_lproj" ] || continue
    macpocket_widget_lproj_dest="$macpocket_widget_bundle/Contents/Resources/$(basename "$macpocket_widget_lproj")"
    mkdir -p "$macpocket_widget_lproj_dest"
    for macpocket_widget_table in "$macpocket_widget_lproj"/*; do
        plutil -lint "$macpocket_widget_table" >/dev/null
        plutil -convert binary1 -o "$macpocket_widget_lproj_dest/$(basename "$macpocket_widget_table")" "$macpocket_widget_table"
    done
done
macpocket_widget_flags=(--force --sign "$macpocket_widget_identity" --entitlements Resources/Widget/MacPocketWidget.entitlements)
if [ "$macpocket_widget_configuration" = release ]; then macpocket_widget_flags+=(--options runtime); fi
if [ "$macpocket_widget_configuration" = release ] && [ "$macpocket_widget_identity" != "-" ]; then macpocket_widget_flags+=(--timestamp); fi
codesign "${macpocket_widget_flags[@]}" "$macpocket_widget_bundle"
codesign --verify --strict "$macpocket_widget_bundle"
