# MacPocket documentation

This is the entry point for contributors. User-facing information (features,
download, install) lives in the [project README](../README.md); release notes are in
the [changelog](../CHANGELOG.md).

## Map

| Area | Document | Read it when you want to… |
| --- | --- | --- |
| Architecture | [Overview](architecture/overview.md) | understand targets, processes and dependency direction |
| Architecture | [Security and privacy](architecture/security-and-privacy.md) | know which permissions, entitlements and data MacPocket touches |
| Architecture | [Conventions](architecture/conventions.md) | write code that matches the codebase |
| Development | [Getting started](development/getting-started.md) | build, run, test and verify locally |
| Development | [Localization](development/localization.md) | add or change user-facing text |
| Development | [Releasing](development/releasing.md) | cut a signed, notarized release |
| Development | [Website](development/website.md) | change or deploy the public site |
| Features | [Catalog](features/catalog.md) | see what each module does and where its limits are |
| Decisions | [Architecture decision records](decisions/README.md) | learn why something is built the way it is |

## Source of truth

Each fact has one owner. Link to it instead of copying it.

| Fact | Owner |
| --- | --- |
| App version and build number | `Resources/Info.plist` |
| Release notes | `CHANGELOG.md` (headings are parsed by the release tooling) |
| Targets and dependencies | `Package.swift` |
| Build, test and release commands | `Makefile` and `scripts/` |
| Minimum macOS version | `Package.swift` and `Resources/Info.plist` (`LSMinimumSystemVersion`) |
| Entitlements and usage strings | `Resources/*.entitlements`, `Resources/Info.plist` |
| User-facing strings | `Resources/*.lproj` |
| Test counts | the test run itself; they are deliberately not written in prose |

If you change one of these, check the documents that link to it.

## Writing rules

- Documentation is written in English.
- Describe what the software does today. Put history in the changelog and the
  reasoning behind a choice in a decision record.
- Do not record dates, test counts or machine names in prose; they go stale.
