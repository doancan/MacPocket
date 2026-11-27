# Localization

MacPocket ships Turkish and English. Both are complete: the release pipeline fails
when an English translation is missing.

## How it works

- **Turkish is the source language.** User-facing strings in code are Turkish
  literals (`Text("…")`, `String(localized: "…")`), and the literal is the key.
- `Resources/tr.lproj/Localizable.strings` holds the Turkish table and
  `Resources/en.lproj/Localizable.strings` the English translations, keyed by the
  Turkish literal. Plural forms live in `Localizable.stringsdict`.
- Structured keys (for example `SSH.keys.addToAgent`) are used where a literal
  would be ambiguous.
- The SSH shortcut recorder package ships its own translations inside
  `Packages/KeyboardShortcuts`.

## Which language the app uses

A fresh install follows the macOS language order. Settings can pin Turkish or English, which writes the app's
own `AppleLanguages` default; choosing *System* again removes it. When none of the user's languages is
supported, the app falls back to English (`CFBundleDevelopmentRegion` in `Resources/Info.plist`).

## Adding or changing text

1. Write the Turkish string in code.
2. Add the English translation to `Resources/en.lproj/Localizable.strings`.
3. Run `scripts/check/localizations.sh`. It compiles the project, extracts every
   localizable literal the compiler sees and reports keys without an English
   translation, plus format-specifier mismatches.
4. `make verify` runs the same check.

Useful options: `--clean` re-extracts from scratch (drops keys of deleted files);
`--stub FILE` writes the missing keys as an English stub to translate.

## Rules

- Never concatenate translated fragments; use format strings so word order can change.
- Keep format specifiers (`%@`, `%d`) identical between languages.
- Remove translations of deleted features in the same change.
