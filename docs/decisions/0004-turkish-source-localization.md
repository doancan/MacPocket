# 0004. Turkish literals as localization keys

Status: Accepted

## Context

The product started as a Turkish-language app and later gained English. Using
SwiftUI's literal-as-key behavior keeps views readable and avoids a parallel key
catalog for several thousand strings.

## Decision

Turkish is the source language. The Turkish literal is the key; English lives in
`Resources/en.lproj`. Structured keys are used only where a literal would be
ambiguous. `scripts/check/localizations.sh`, run by `make verify` and by the release
workflow, fails on any key without an English translation or with mismatched format
specifiers.

## Consequences

- Fixing a Turkish typo changes the key and requires editing both tables.
- Contributors who do not read Turkish still add text through the check's English
  stub output (`--stub`), and a maintainer reviews the Turkish source string.
- Adding a language means adding one `.lproj` table; the check can be extended per language.
- Revisit if the contributor base grows: moving to English source keys would remove
  the typo-as-key coupling at the cost of a one-time migration.
