# Security policy

## Supported versions

Only the latest release receives security fixes. The app updates itself through
Sparkle, so users normally run the latest version.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private
vulnerability reporting: **Security → Report a vulnerability** on this repository.

Include the affected version, macOS version, reproduction steps and the impact you
expect. You will get an acknowledgement within a few days. Fixes ship as a patch
release, and the changelog credits the reporter unless they prefer otherwise.

## Scope

In scope: the privileged helper and its XPC interface, the network extension,
credential handling for AI usage tracking, file removal and uninstall logic, and the
update and signing pipeline. See
[Security and privacy](docs/architecture/security-and-privacy.md) for the design.
