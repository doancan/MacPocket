#!/bin/bash
# The public site must agree with the sources it mirrors: the generated changelog page matches CHANGELOG.md, and
# the download button names the disk image the release workflow actually attaches.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
python3 -I scripts/site/build-changelog.py --check

asset="MacPocket-macOS-arm64.dmg"
grep -q "$asset" .github/workflows/release.yml || { echo "site: release workflow no longer attaches $asset" >&2; exit 1; }
for page in site/index.html site/tr/index.html site/changelog/index.html; do
    grep -q "releases/latest/download/$asset" "$page" || { echo "site: $page does not link the latest $asset" >&2; exit 1; }
done
echo "site: download link and changelog consistent"
