# Getting started

## Requirements

- Apple Silicon Mac running the macOS version required by `Package.swift`
- The matching Xcode release (Swift tools version in `Package.swift`)
- No other toolchain: dependencies are resolved by SwiftPM

## Everyday commands

| Command | What it does |
| --- | --- |
| `make build` | Debug build of every target |
| `make test` | Run the unit and integration tests |
| `make verify` | App tests, the local packages' own tests and the localization completeness check. **Run before every push**. `make -j3 verify` runs the three parts in parallel |
| `make app` | Build `.build/MacPocket.app` (debug, debugger attachable) |
| `make app-release` | Optimized app without debugger entitlement |
| `make install-local` | Install the optimized app to `~/Applications` and relaunch it |
| `make dmg` | Release app plus the drag-to-install disk image |
| `make probe` | Run the `macpocket-probe` diagnostics CLI |

`macpocket-probe` exposes the core services without the UI, for example
`swift run macpocket-probe system` or `swift run macpocket-probe processes`.

## Signing and permissions

`scripts/build/build-app.sh` signs with the first valid *Developer ID Application* or
*Apple Development* identity in your keychain. Set `MACPOCKET_SIGN_IDENTITY` to
choose one explicitly. Without any identity the build is ad-hoc signed, and macOS
resets Accessibility and Screen Recording grants on every rebuild, so use a real
identity for day-to-day work.

`MACPOCKET_NOTARY_PROFILE` (a `notarytool store-credentials` profile) enables local
notarization.

## Tests

- One XCTest target per module under `Tests/`; shared fixtures live in
  `Tests/MacPocketTestSupport`.
- Mock only system boundaries (network, clock, third-party APIs). Tests that need
  real hardware, a connected trackpad or live network are opt-in and skip by default.
- Behavior bugs are fixed with a failing regression test first.
- `scripts/audit/` drives a debug build against owned fixture apps to exercise
  real AppKit, Accessibility and WindowServer behavior without touching other
  applications. These are manual checks, not part of CI.
- `scripts/bench/` holds the benchmarks and their sources.

## Scripts

| Directory | Contents |
| --- | --- |
| `scripts/build/` | App bundle, disk image, widget and network filter embedding, local install |
| `scripts/release/` | Appcast generation |
| `scripts/check/` | Localization completeness, installer artwork strings, file-shelf promise check |
| `scripts/data/` | Refresh of the bundled offline databases |
| `scripts/audit/` | Manual runtime audits and their fixture apps |
| `scripts/bench/` | Benchmarks |

Each script finds the repository root itself, so it can be run from any directory.

## Screenshots

README images live in `docs/assets/`. Capture the app window with
`screencapture -x -o -l <window id>` and blur anything personal (computer name, IP
addresses, SSIDs, file names) before committing; a real Mac shows all of them.

## Offline data

The manufacturer lookup databases in `Resources/` are bundled snapshots; the app
never downloads them. Refresh them with `scripts/data/update-oui.sh` (IEEE registries)
and `scripts/data/update-maclookup.sh` (MACLookup), then commit the result.
