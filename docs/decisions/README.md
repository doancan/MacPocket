# Architecture decision records

A decision record explains why something is built the way it is. Write one when a
choice is hard to reverse (more than a day of work), picks between two reasonable
alternatives, or is likely to prompt "why is it like this?".

Records are immutable. To change a decision, add a new record that supersedes the
old one and update the old record's status.

| ID | Title | Status |
| --- | --- | --- |
| [0001](0001-vendored-local-packages.md) | Vendor third-party code as local packages | Accepted |
| [0002](0002-sparkle-updates-via-github-releases.md) | Ship updates with Sparkle and GitHub Releases | Accepted |
| [0003](0003-privileged-helper-over-xpc.md) | Isolate privileged work in an XPC helper | Accepted |
| [0004](0004-turkish-source-localization.md) | Turkish literals as localization keys | Accepted |

## Template

```markdown
# NNNN. Title

Status: Proposed | Accepted | Superseded by NNNN

## Context
## Decision
## Consequences
```
