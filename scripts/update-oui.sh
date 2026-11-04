#!/bin/bash
# Rebuilds Resources/oui.tsv.lzfse from the IEEE public registries (MA-L, MA-M, MA-S and historical IAB).
# The app never downloads this itself; refresh it now and then during development.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for path in oui/oui.txt oui28/mam.txt oui36/oui36.txt iab/iab.txt; do
    curl -fsSL --max-time 300 -H "User-Agent: curl/8" -o "$work/$(basename "$path")" "https://standards-oui.ieee.org/$path"
done
/usr/bin/python3 -I - "$work" "$work/oui.tsv" <<'PY'
import os, re, sys
source, target = sys.argv[1:]
rows = {}
def load(name, digits):
    prefix = None
    for line in open(os.path.join(source, name), encoding="utf-8", errors="replace"):
        match = re.match(r"^([0-9A-F]{2})-([0-9A-F]{2})-([0-9A-F]{2})\s+\(hex\)", line)
        if match:
            prefix = "".join(match.groups()); continue
        match = re.match(r"^([0-9A-F]{6})(?:-[0-9A-F]{6})?\s+\(base 16\)\s+(.+?)\s*$", line)
        if match and prefix and match.group(2):
            key = (prefix + match.group(1))[:digits] if digits > 6 else match.group(1)
            if match.group(2).lower() != "private":
                rows[key] = match.group(2).replace("\t", " ")
            prefix = None
load("oui.txt", 6); load("iab.txt", 9); load("mam.txt", 7); load("oui36.txt", 9)
with open(target, "w", encoding="utf-8") as handle:
    for key in sorted(rows):
        handle.write(f"{key}\t{rows[key]}\n")
print(f"{len(rows)} prefixes")
PY
cat > "$work/compress.swift" <<'SWIFT'
import Foundation
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
try ((input as NSData).compressed(using: .lzfse) as Data).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT
swift "$work/compress.swift" "$work/oui.tsv" "$root/Resources/oui.tsv.lzfse"
ls -l "$root/Resources/oui.tsv.lzfse"
