# 0002. Ship updates with Sparkle and GitHub Releases

Status: Accepted

## Context

The app is distributed outside the Mac App Store because it needs a privileged
helper, a network system extension and broad system access. It still needs
trustworthy automatic updates without running a server.

## Decision

Use Sparkle 2. The appcast (`appcast.xml`) is generated in CI from the matching
`CHANGELOG.md` section and attached to each GitHub release; `SUFeedURL` points to
`releases/latest/download/appcast.xml`. Archives are signed with an EdDSA key held
as a CI secret; the public key is in `Info.plist`. System profiling is disabled.

## Consequences

- Publishing a release is the only step needed to ship an update.
- The changelog heading format is a contract with the release tooling.
- Losing the Sparkle private key would force users to reinstall manually, so the key
  must be backed up outside CI.
- Updates depend on GitHub availability.
