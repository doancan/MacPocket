#!/bin/bash
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
macpocket_configuration="${1:-debug}"
case "$macpocket_configuration" in debug|release) ;; *) echo "debug veya release seçin." >&2; exit 1 ;; esac
# Release imzası için isteğe bağlı: MACPOCKET_SIGN_IDENTITY="Developer ID Application: …"
# Notarization için isteğe bağlı: MACPOCKET_NOTARY_PROFILE=<xcrun notarytool store-credentials profili>
# Without an explicit identity, prefer a valid Developer ID / Apple Development certificate: macOS ties
# Accessibility and Screen Recording grants to the signing identity, while ad-hoc grants reset on every build.
if [ -z "${MACPOCKET_SIGN_IDENTITY:-}" ]; then
    macpocket_valid_identities="$(security find-identity -v -p codesigning 2>/dev/null | grep -v REVOKED || true)"
    MACPOCKET_SIGN_IDENTITY="$( { grep '"Developer ID Application:' <<<"$macpocket_valid_identities"; grep '"Apple Development:' <<<"$macpocket_valid_identities"; } | head -1 | awk '{print $2}' || true)"
fi
macpocket_identity="${MACPOCKET_SIGN_IDENTITY:--}"
echo "İmza kimliği: $macpocket_identity" >&2
swift build -c "$macpocket_configuration" --product MacPocket
swift build -c "$macpocket_configuration" --product MacPocketFanHelper
macpocket_binary_dir="$(swift build -c "$macpocket_configuration" --show-bin-path)"
macpocket_app_dir="$macpocket_root/.build/MacPocket.app"
rm -rf "$macpocket_app_dir"
mkdir -p "$macpocket_app_dir/Contents/MacOS"
mkdir -p "$macpocket_app_dir/Contents/Resources"
install -m 755 "$macpocket_binary_dir/MacPocket" "$macpocket_app_dir/Contents/MacOS/MacPocket"
install -m 755 "$macpocket_binary_dir/MacPocketFanHelper" "$macpocket_app_dir/Contents/MacOS/MacPocketFanHelper"
mkdir -p "$macpocket_app_dir/Contents/Library/LaunchDaemons"
install -m 644 Resources/Daemons/com.doancan.MacPocket.FanHelper.plist "$macpocket_app_dir/Contents/Library/LaunchDaemons/"
plutil -lint "$macpocket_app_dir/Contents/Library/LaunchDaemons/com.doancan.MacPocket.FanHelper.plist" >/dev/null
install -m 644 Resources/Info.plist "$macpocket_app_dir/Contents/Info.plist"
install -m 644 Resources/AppIcon.icns "$macpocket_app_dir/Contents/Resources/AppIcon.icns"
for macpocket_lproj in Resources/*.lproj; do
    [ -d "$macpocket_lproj" ] || continue
    macpocket_lproj_dest="$macpocket_app_dir/Contents/Resources/$(basename "$macpocket_lproj")"
    mkdir -p "$macpocket_lproj_dest"
    for macpocket_table in "$macpocket_lproj"/*; do
        # Validate and ship tables in binary form, as Xcode does.
        plutil -lint "$macpocket_table" >/dev/null
        plutil -convert binary1 -o "$macpocket_lproj_dest/$(basename "$macpocket_table")" "$macpocket_table"
        chmod 644 "$macpocket_lproj_dest/$(basename "$macpocket_table")"
    done
done
plutil -lint "$macpocket_app_dir/Contents/Info.plist" >/dev/null
# The helper is signed on its own, before the app seals it into the bundle.
macpocket_helper_flags=(--force --identifier com.doancan.MacPocket.FanHelper --sign "$macpocket_identity")
if [ "$macpocket_configuration" = release ]; then macpocket_helper_flags+=(--options runtime); fi
if [ "$macpocket_configuration" = release ] && [ "$macpocket_identity" != "-" ]; then macpocket_helper_flags+=(--timestamp); fi
codesign "${macpocket_helper_flags[@]}" "$macpocket_app_dir/Contents/MacOS/MacPocketFanHelper"
if [ "$macpocket_configuration" = debug ]; then
    codesign --force --sign "$macpocket_identity" --entitlements Resources/MacPocket.entitlements "$macpocket_app_dir"
else
    # Hardened runtime is required for notarization; it needs no extra entitlements for this app.
    # Hardened runtime blocks Apple events to other apps (Finder, System Events) without this entitlement.
    macpocket_sign_flags=(--force --options runtime --entitlements Resources/MacPocketRelease.entitlements --sign "$macpocket_identity")
    if [ "$macpocket_identity" != "-" ]; then macpocket_sign_flags+=(--timestamp); fi
    codesign "${macpocket_sign_flags[@]}" "$macpocket_app_dir"
fi
codesign --verify --strict --verbose=1 "$macpocket_app_dir"
if [ "$macpocket_configuration" = release ]; then
    macpocket_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    macpocket_zip="$macpocket_root/.build/MacPocket-$macpocket_version-$(uname -m).zip"
    rm -f "$macpocket_zip"
    ditto -c -k --keepParent "$macpocket_app_dir" "$macpocket_zip"
    if [ -n "${MACPOCKET_NOTARY_PROFILE:-}" ]; then
        if [ "$macpocket_identity" = "-" ]; then echo "Notarization için MACPOCKET_SIGN_IDENTITY gerekir." >&2; exit 1; fi
        xcrun notarytool submit "$macpocket_zip" --keychain-profile "$MACPOCKET_NOTARY_PROFILE" --wait
        xcrun stapler staple "$macpocket_app_dir"
        rm -f "$macpocket_zip"
        ditto -c -k --keepParent "$macpocket_app_dir" "$macpocket_zip"
    fi
    echo "$macpocket_zip"
fi
echo "$macpocket_app_dir"
