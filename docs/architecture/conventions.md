# Conventions

## Code

- Swift 6 language mode with strict concurrency. UI types are `@MainActor`;
  shared mutable state is isolated in actors. Every `@unchecked Sendable` needs a
  comment explaining the invariant that makes it safe.
- No force unwraps, `try!` or empty `catch` in production code. Errors are typed and
  carry context; user-facing messages are safe and localized, details go to the log.
- System access (IOKit, XPC, file system, network, processes) sits behind a protocol
  so the logic above it is testable. Long-running or external processes go through
  `BoundedProcess` with a timeout.
- Lists and scans are bounded and paginated; filesystem walks check for cancellation.
- UI that shows data has loading, error and empty states, accessibility labels, and
  protection against double submission.
- Removal and uninstall paths go through the protected-path checks in `FileRemoval`.
- Prefer extending an existing helper to writing a near-duplicate.

## Git

- Branches: `feature/`, `fix/`, `chore/`, `refactor/`, `docs/`.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/) in
  English, one logical change each, and each commit passes `make verify`.
- Pull requests describe the user-visible change and how it was verified.

## Dependencies

A new dependency, pattern or layer needs a decision record in
[`docs/decisions`](../decisions/README.md). Vendored packages record their upstream
and local changes (see `Packages/AIUsageKit/UPSTREAM.json`).
