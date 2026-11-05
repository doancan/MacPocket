#!/bin/bash
# Extracts every localizable key the compiler sees (LocalizedStringKey / LocalizedStringResource literals,
# String(localized:), Text, Button, Label, …) and fails when one has no English translation.
#   scripts/check-localizations.sh              check, list missing keys per source file
#   scripts/check-localizations.sh --clean      re-extract from scratch (drops keys of deleted files)
#   scripts/check-localizations.sh --stub FILE  also write missing keys to FILE as an English stub to translate
# Environment (for parallel work): MACPOCKET_LOC_SCRATCH=<name> separate build dir; MACPOCKET_LOC_EXTRA=<a.strings:b.json>
# extra English tables (.strings, or .json {"key": {"one": "...", "other": "..."}}); MACPOCKET_LOC_ONLY=<regex> report only
# source paths matching it.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$macpocket_root"
macpocket_scratch="$macpocket_root/.build/localization-build${MACPOCKET_LOC_SCRATCH:+-$MACPOCKET_LOC_SCRATCH}"
macpocket_strings="$macpocket_root/.build/localized-strings${MACPOCKET_LOC_SCRATCH:+-$MACPOCKET_LOC_SCRATCH}"
macpocket_stub=""
while [ $# -gt 0 ]; do
    case "$1" in
        --clean) rm -rf "$macpocket_scratch" "$macpocket_strings" ;;
        --stub) macpocket_stub="$2"; shift ;;
        *) echo "Bilinmeyen seçenek: $1" >&2; exit 2 ;;
    esac
    shift
done
mkdir -p "$macpocket_strings"
swift build --scratch-path "$macpocket_scratch" --product MacPocket \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$macpocket_strings" >&2
/usr/bin/python3 -I - "$macpocket_strings" "$macpocket_root/Resources" "$macpocket_stub" "${MACPOCKET_LOC_EXTRA:-}" "${MACPOCKET_LOC_ONLY:-}" <<'PY'
import json, os, re, subprocess, sys

strings_dir, resources, stub, extra, only = sys.argv[1:6]
sources = os.path.join(os.path.dirname(resources), "Sources")
source_roots = [sources, os.path.join(os.path.dirname(resources), "Packages", "SSHConfigKit", "Sources")]

def load_table(path):
    if not os.path.exists(path):
        return {}
    if path.endswith(".json"):
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if not re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S).strip():
        return {}
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True)
    if result.returncode != 0:
        sys.exit(f"Okunamayan tablo: {path}\n{result.stderr.decode()}")
    return json.loads(result.stdout)

keys = {}
for name in sorted(os.listdir(strings_dir)):
    if not name.endswith(".stringsdata"):
        continue
    with open(os.path.join(strings_dir, name), encoding="utf-8") as handle:
        document = json.load(handle)
    source = document.get("source", name)
    if not os.path.exists(source) or not any(os.path.realpath(source).startswith(os.path.realpath(root) + os.sep) for root in source_roots):
        continue
    if only and not re.search(only, source):
        continue
    for entry in document.get("tables", {}).get("Localizable", []):
        keys.setdefault(entry["key"], set()).add((os.path.relpath(source, os.path.dirname(resources)), entry["location"]["startingLine"]))

english = load_table(os.path.join(resources, "en.lproj", "Localizable.strings"))
english_plurals = load_table(os.path.join(resources, "en.lproj", "Localizable.stringsdict"))
for path in filter(None, extra.split(":")):
    table = load_table(path)
    if path.endswith(".json"):
        english_plurals.update(table)
    else:
        english.update({k: v for k, v in table.items() if k not in english})
specifier = re.compile(r"%(?:\d+\$)?(?:lld|ld|lu|llu|d|i|u|@|f|\.\d+f|lf|s)")

def needs_translation(key):
    # Keys without letters once format specifiers are removed ("%@", "%lld", "—") need no entry.
    return re.search(r"[^\W\d_]", specifier.sub("", key)) is not None

missing = sorted(k for k in keys if needs_translation(k) and k not in english and k not in english_plurals)
mismatched = []
for key, value in english.items():
    if key in keys and sorted(re.sub(r"\d+\$", "", s) for s in specifier.findall(key)) != \
            sorted(re.sub(r"\d+\$", "", s) for s in specifier.findall(value)):
        mismatched.append(key)
unused = sorted(k for k in english if k not in keys)

by_file = {}
for key in missing:
    for path, line in sorted(keys[key]):
        by_file.setdefault(path, []).append((line, key))
for path in sorted(by_file):
    print(f"{path}:")
    for line, key in sorted(by_file[path]):
        print(f"  {line}: {key}")
for key in mismatched:
    print(f"Biçim belirteçleri uyuşmuyor: {key!r} -> {english[key]!r}")
if stub and missing:
    def escape(text):
        return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    with open(stub, "w", encoding="utf-8") as handle:
        for key in missing:
            handle.write(f'"{escape(key)}" = "{escape(key)}";\n')
print(f"{len(keys)} anahtar · {len(missing)} eksik İngilizce çeviri · {len(mismatched)} biçim uyuşmazlığı · {len(unused)} kullanılmayan çeviri")
shortcut_localizations = os.path.join(os.path.dirname(resources), "Packages", "KeyboardShortcuts", "Sources", "KeyboardShortcuts", "Localization")
shortcut_en = load_table(os.path.join(shortcut_localizations, "en.lproj", "Localizable.strings"))
shortcut_tr = load_table(os.path.join(shortcut_localizations, "tr.lproj", "Localizable.strings"))
shortcut_missing = sorted(set(shortcut_en) - set(shortcut_tr))
shortcut_mismatched = sorted(k for k in shortcut_en if k in shortcut_tr and
    sorted(specifier.findall(shortcut_en[k])) != sorted(specifier.findall(shortcut_tr[k])))
for key in shortcut_missing:
    print(f"Kısayol kaydedicisinde eksik Türkçe çeviri: {key}")
for key in shortcut_mismatched:
    print(f"Kısayol kaydedicisinde biçim uyuşmazlığı: {key}")
print(f"Kısayol kaydedicisi: {len(shortcut_en)} anahtar · {len(shortcut_missing)} eksik Türkçe çeviri · {len(shortcut_mismatched)} biçim uyuşmazlığı")
sys.exit(1 if missing or mismatched or shortcut_missing or shortcut_mismatched else 0)
PY
