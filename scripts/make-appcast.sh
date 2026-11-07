#!/bin/bash
# Builds the Sparkle appcast for one release zip.
# Usage: scripts/make-appcast.sh <zip> <output appcast.xml>
# The EdDSA private key comes from SPARKLE_ED_PRIVATE_KEY (CI, passed on stdin, never written to disk) or, when that
# is unset, from the login keychain entry created by `generate_keys --account MacPocket` (local runs).
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
zip="$1"
output="$2"
[ -f "$zip" ] || { echo "Zip bulunamadı: $zip" >&2; exit 1; }
sign_update="$macpocket_root/.build/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$sign_update" ] || (cd "$macpocket_root" && swift package resolve >/dev/null)
info="$macpocket_root/Resources/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")"
feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info")"
repository="${feed%/releases/*}"

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    signature="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$zip")"
else
    signature="$("$sign_update" --account MacPocket "$zip")"
fi
# sign_update prints: sparkle:edSignature="…" length="…"
[[ "$signature" == *'sparkle:edSignature="'*'length="'* ]] || { echo "İmza alınamadı." >&2; exit 1; }

python3 - "$macpocket_root/CHANGELOG.md" "$version" "$build" "$minimum" "$repository" "$(basename "$zip")" "$signature" "$output" <<'PY'
import html, re, sys
from email.utils import formatdate
changelog, version, build, minimum, repository, zip_name, signature, output = sys.argv[1:]

def section(text, version):
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside: break
            inside = line[3:].strip().startswith(version)
            continue
        if inside: lines.append(line)
    return lines

def inline(text):
    text = html.escape(text, quote=False)
    def link(match):
        label, target = match.groups()
        if target.startswith('docs/'):
            target = f'{repository}/blob/v{version}/{target}'
        if not target.startswith('https://'): return label
        return f'<a href="{html.escape(target, quote=True)}">{label}</a>'
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, text)
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)

body, in_list = [], False
for line in section(open(changelog, encoding="utf-8").read(), version):
    if line.startswith("### "):
        if in_list: body.append("</ul>"); in_list = False
        body.append(f"<h3>{inline(line[4:].strip())}</h3>")
    elif line.startswith("- "):
        if not in_list: body.append("<ul>"); in_list = True
        body.append(f"<li>{inline(line[2:].strip())}</li>")
if in_list: body.append("</ul>")
notes = "\n".join(body) or f"<p>MacPocket {html.escape(version)}</p>"

url = f"{repository}/releases/download/v{version}/{zip_name}"
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MacPocket</title>
    <link>{repository}</link>
    <item>
      <title>MacPocket {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(minimum)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{repository}/releases/tag/v{html.escape(version)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" type="application/octet-stream" {signature} />
    </item>
  </channel>
</rss>
"""
open(output, "w", encoding="utf-8").write(xml)
PY
xmllint --noout "$output"
echo "$output"
