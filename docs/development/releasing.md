# Releasing

Releases are produced by `.github/workflows/release.yml` when a `v*` tag is pushed
(or the workflow is dispatched manually for a tag).

## Checklist

1. Update the version in `Resources/Info.plist`: `CFBundleShortVersionString` and
   an incremented `CFBundleVersion`.
2. Add a section to `CHANGELOG.md` for the version (see [Changelog format](#changelog-format)).
   The release workflow and `scripts/release/make-appcast.sh` extract the notes for that
   version by its heading.
3. Run `make verify`, commit, and push to `main`.
4. Wait for the **CI** check on that commit to pass.
5. Tag the commit: `git tag -a v<version> -m "MacPocket <version>" && git push origin v<version>`.

The workflow refuses to run if the tag does not equal `v` + the version in
`Info.plist`, if the commit has no passing CI run, or if the changelog section is empty.
If you tagged before CI finished, wait for it and re-run the workflow.

## Changelog format

Each release has one section, newest first. The heading shape is fixed because the
release tooling parses it: `## <version> — <Month D, YYYY>` (em dash, no emoji).

Below it, use only these subheadings, in this order, and omit the empty ones:

| Heading | Use for |
| --- | --- |
| `### Features` | A new feature or capability |
| `### Improved` | Better performance, accuracy, polish or accessibility of something that already exists |
| `### Changed` | A behavior or layout change that is neither a fix nor an improvement |
| `### Fixed` | A bug fix, including crashes |
| `### Removed` | A feature or option that was taken out |
| `### Security` | Permissions, credentials, data protection or hardening |

Bullets read `- **Area:** One or two plain sentences.` where *Area* is the feature or
page name. Write in the third person, state what changed and what users notice, and
leave out internal task names, commit or issue links and emoji. Items in the
changelog that are visible to users become the GitHub release notes and the Sparkle
update dialog, so write them for users, not for maintainers.

## What the pipeline does

1. Checks the tag against `Info.plist`.
2. Checks that CI (`make verify`: tests, package tests, localizations) passed for the tagged commit.
3. Imports the Developer ID certificate into a temporary keychain.
4. Builds the signed Apple Silicon app (including the helper, widget and network
   filter) and notarizes and staples it.
5. Builds, notarizes and staples the disk image.
6. Signs the update zip with the Sparkle EdDSA key and generates `appcast.xml`.
7. Creates the GitHub release with the zip, the dmg, `SHA256SUMS` and `appcast.xml`.
8. Deletes the temporary keychain and signing material.

The app's `SUFeedURL` points at `releases/latest/download/appcast.xml`, so
publishing a release is what ships the update to existing installs.

## Secrets

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID Application certificate |
| `APPLE_TEAM_ID` | Team for signing and notarization |
| `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` | Notarization credentials |
| `MACPOCKET_FILTER_HOST_PROFILE`, `MACPOCKET_FILTER_PROVIDER_PROFILE` | Provisioning profiles for the network filter |
| `SPARKLE_ED_PRIVATE_KEY` | Signs update archives; the public key is in `Info.plist` |

Never commit signing inputs; `.gitignore` excludes certificates and profiles.

## Rolling back

Delete the GitHub release and tag, or publish a new patch release. Sparkle clients
follow whichever appcast `latest` serves, so a fixed patch release supersedes a bad one.
