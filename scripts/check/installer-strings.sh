#!/bin/bash
# The disk image artwork is drawn by scripts/build/render-installer.swift. The compiler's string extraction never
# sees that script, so its English translations look unused and have been pruned before, which broke the release
# at the disk image step. Fail here, in CI, instead of there.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$root" <<'EOF'
import json, re, subprocess, sys

root = sys.argv[1]
english = json.loads(subprocess.check_output(
    ["plutil", "-convert", "json", "-o", "-", f"{root}/Resources/en.lproj/Localizable.strings"]))
source = open(f"{root}/scripts/build/render-installer.swift", encoding="utf-8").read()
keys = re.findall(r'^let (?:heading|instruction|completion) = "(.*)"$', source, re.M)
if len(keys) != 3:
    sys.exit(f"installer strings: expected 3 string constants in render-installer.swift, found {len(keys)}")
missing = [key for key in keys if key not in english]
if missing:
    sys.exit("installer strings: missing English translation for " + ", ".join(missing))
print(f"installer strings: {len(keys)} keys, 0 missing English translations")
EOF
