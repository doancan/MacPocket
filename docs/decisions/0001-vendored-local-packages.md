# 0001. Vendor third-party code as local packages

Status: Accepted

## Context

MacPocket integrates three pieces of external code: a global shortcut recorder
(`KeyboardShortcuts`), AI provider usage transport (`AIUsageKit`, derived from an
MIT-licensed project) and the SSH configuration engine (`SSHConfigKit`). Each needs
local changes such as translations, renamed diagnostics and removed standalone
updaters or installers. Upstream releases cannot be pinned to a state that already
contains those changes.

## Decision

Keep them as local Swift packages under `Packages/`, each with its own tests; the
third-party ones keep their license file. Record upstream repository, revision and local modifications next to
the code (`Packages/AIUsageKit/UPSTREAM.json`). Application code depends on the
packages' public products only.

## Consequences

- Builds are reproducible without network access to upstream.
- Upstream fixes must be merged by hand; the recorded revision shows the base.
- License texts ship in the app bundle, and the root `THIRD_PARTY_NOTICES.md` lists them.
