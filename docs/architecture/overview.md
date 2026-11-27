# Architecture overview

MacPocket is a native macOS app (Swift 6, SwiftUI with AppKit where needed) built
with Swift Package Manager. It targets Apple Silicon and the macOS version declared
in `Package.swift`.

## Targets

| Target | Kind | Responsibility |
| --- | --- | --- |
| `MacPocketShared` | library | Types shared between the app and its extensions |
| `MacPocketCore` | library | Domain and system services: sampling, disk, network, power, cleanup, clipboard, window logic. No UI |
| `MacPocketNetworkPolicy` | library | Rule model and matching for per-app internet control |
| `MacPocketAIUsage` | library | AI subscription quota tracking (accounts, credentials, refresh) on top of `UsageCore` |
| `MacPocketSSH` | library | SSH manager UI and runtime on top of `SSHConfigKit` |
| `MacPocketWidgetUI` | library | Widget views and timeline logic |
| `MacPocketApp` | executable | The app: SwiftUI views, panels, services, menu bar |
| `MacPocketHelper` | executable | Privileged helper (installed as a launch daemon) |
| `MacPocketNetworkFilter` | executable | Network Extension content filter for internet control |
| `MacPocketWidget` | executable | WidgetKit extension |
| `MacPocketProbe` | executable | Command-line front end to `MacPocketCore` for diagnostics |
| `MacPocketTestSupport` | library | Shared test fixtures and doubles |

Local packages under `Packages/`:

| Package | Purpose | License |
| --- | --- | --- |
| `SSHConfigKit` | SSH config parser, known_hosts, key management, atomic writes | MIT (project license) |
| `KeyboardShortcuts` | Global shortcut recorder and registration (vendored 2.4.0) | MIT |
| `AIUsageKit` | Provider transport, decoders and scheduling for AI quotas | MIT |

External dependency: [Sparkle](https://github.com/sparkle-project/Sparkle) for
in-app updates.

## Dependency direction

```
MacPocketApp ──► MacPocketCore ──► MacPocketShared
      │                              ▲
      ├──► MacPocketSSH ──► SSHConfigKit, KeyboardShortcuts
      ├──► MacPocketAIUsage ──► MacPocketCore, UsageCore
      └──► MacPocketNetworkPolicy ◄── MacPocketNetworkFilter
MacPocketHelper ──► MacPocketCore
MacPocketWidget ──► MacPocketWidgetUI ──► MacPocketShared
```

- Domain code in `MacPocketCore` does not import SwiftUI. Views live in
  `MacPocketApp` and call services through protocols so tests can substitute
  doubles.
- Feature modules (`SSH`, `AIUsage`) depend only on the public surface of the
  packages they wrap.
- The compiler enforces these boundaries through the target graph in `Package.swift`.

## Processes

| Process | Privilege | Why it exists |
| --- | --- | --- |
| App (`MacPocket`) | User | UI, menu bar, all unprivileged features |
| Helper (`MacPocketFanHelper`) | root, launch daemon | SMC fan writes and LAN MAC discovery; validates every request and returns fans to macOS if the app stops responding or the machine runs hot. Talks to the app over XPC (`MacPocketHelperProtocol`) |
| Network filter | system extension | Allows or blocks new connections by signed app identity |
| Widget | sandboxed extension | Shows disk usage on the desktop |

State that outlives a process (preferences, clipboard history, metric history) is
stored in the user's Application Support and `UserDefaults`; the helper holds no
persistent state and restores safe defaults when it restarts.

## Repository layout

```
Sources/          Swift targets listed above
Packages/         Local Swift packages
Resources/        Info.plists, entitlements, icons, localizations, offline databases
Tests/            Unit and integration tests, one test target per module
scripts/          Build, release, check, data, audit and benchmark scripts
site/             Public website (static HTML and CSS)
docs/             Documentation and README images
.github/          CI workflows
```
