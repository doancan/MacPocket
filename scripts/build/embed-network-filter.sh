#!/bin/bash
# Called by build-app.sh only when both explicit provisioning-profile paths are provided.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$macpocket_root"
macpocket_filter_app="$1"
macpocket_filter_configuration="$2"
macpocket_filter_identity="$3"
macpocket_filter_base_entitlements="$4"
macpocket_filter_work="$macpocket_root/.build/network-filter-$macpocket_filter_configuration"
mkdir -p "$macpocket_filter_work"
if [ "$macpocket_filter_identity" = "-" ]; then echo "Network Extension requires a provisioned signing identity." >&2; exit 1; fi
: "${MACPOCKET_FILTER_HOST_PROFILE:?Set the host provisioning profile path}"
: "${MACPOCKET_FILTER_PROVIDER_PROFILE:?Set the provider provisioning profile path}"
security cms -D -i "$MACPOCKET_FILTER_HOST_PROFILE" > "$macpocket_filter_work/host-profile.plist"
security cms -D -i "$MACPOCKET_FILTER_PROVIDER_PROFILE" > "$macpocket_filter_work/provider-profile.plist"
python3 - "$macpocket_filter_work" "$macpocket_filter_base_entitlements" <<'PY'
import datetime,pathlib,plistlib,sys
work=pathlib.Path(sys.argv[1]);base=plistlib.loads(pathlib.Path(sys.argv[2]).read_bytes())
capability='content-filter-provider-systemextension'
profiles=[]
for name,bundle in [('host','com.doancan.MacPocket'),('provider','com.doancan.MacPocket.NetworkFilter')]:
 p=plistlib.loads((work/f'{name}-profile.plist').read_bytes());e=p.get('Entitlements',{})
 team=p.get('TeamIdentifier',[''])[0]
 expiry=p.get('ExpirationDate')
 if not team or not expiry or expiry.replace(tzinfo=datetime.timezone.utc)<=datetime.datetime.now(datetime.timezone.utc):
  sys.exit(f'{name}: profile is expired or missing a team identifier')
 if e.get('com.apple.application-identifier') != team+'.'+bundle or capability not in e.get('com.apple.developer.networking.networkextension',[]):
  sys.exit(f'{name}: profile does not authorize the exact bundle identifier and content filter capability')
 if name=='host' and e.get('com.apple.developer.system-extension.install') is not True:
  sys.exit('host: system-extension.install capability is missing')
 profiles.append((team,e))
if profiles[0][0]!=profiles[1][0]:sys.exit('Host and provider profiles must belong to the same team')
for name,bundle in [('host','com.doancan.MacPocket'),('provider','com.doancan.MacPocket.NetworkFilter')]:
 ent=dict(base) if name=='host' else {'com.apple.security.app-sandbox':True}
 ent.update({'com.apple.developer.networking.networkextension':[capability],
             'com.apple.developer.team-identifier':profiles[0][0], 'com.apple.application-identifier':profiles[0][0]+'.'+bundle})
 if name=='host':ent['com.apple.developer.system-extension.install']=True
 (work/f'{name}.entitlements').write_bytes(plistlib.dumps(ent))
PY
swift build -c "$macpocket_filter_configuration" --product MacPocketNetworkFilter
macpocket_filter_bin="$(swift build -c "$macpocket_filter_configuration" --show-bin-path)"
macpocket_filter_bundle="$macpocket_filter_app/Contents/Library/SystemExtensions/com.doancan.MacPocket.NetworkFilter.systemextension"
mkdir -p "$macpocket_filter_bundle/Contents/MacOS"
install -m 755 "$macpocket_filter_bin/MacPocketNetworkFilter" "$macpocket_filter_bundle/Contents/MacOS/MacPocketNetworkFilter"
install -m 644 "$MACPOCKET_FILTER_PROVIDER_PROFILE" "$macpocket_filter_bundle/Contents/embedded.provisionprofile"
install -m 644 "$MACPOCKET_FILTER_HOST_PROFILE" "$macpocket_filter_app/Contents/embedded.provisionprofile"
mkdir -p "$macpocket_filter_bundle/Contents/Resources"
for macpocket_filter_localization in Resources/NetworkFilter/*.lproj; do
    ditto "$macpocket_filter_localization" "$macpocket_filter_bundle/Contents/Resources/$(basename "$macpocket_filter_localization")"
done
python3 - "$macpocket_filter_bundle/Contents/Info.plist" <<'PY'
import pathlib,plistlib,sys
info=plistlib.loads(pathlib.Path('Resources/NetworkFilter/Info.plist').read_bytes())
host=plistlib.loads(pathlib.Path('Resources/Info.plist').read_bytes())
for key in ('CFBundleVersion','CFBundleShortVersionString'):info[key]=host[key]
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
macpocket_filter_flags=(--force --sign "$macpocket_filter_identity" --entitlements "$macpocket_filter_work/provider.entitlements")
if [ "$macpocket_filter_configuration" = release ]; then macpocket_filter_flags+=(--options runtime --timestamp); fi
codesign "${macpocket_filter_flags[@]}" "$macpocket_filter_bundle"
codesign --verify --strict "$macpocket_filter_bundle"
