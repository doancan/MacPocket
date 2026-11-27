# 0003. Isolate privileged work in an XPC helper

Status: Accepted

## Context

Fan control (SMC writes) and LAN MAC discovery need root. Running the whole app
with elevated rights, or shelling out to `sudo`, would widen the attack surface and
break the user-level sandboxing of everything else.

## Decision

Install a small launch daemon (`MacPocketFanHelper`, registered through
`SMAppService`) that exposes typed operations over XPC (`MacPocketHelperProtocol`).
The helper checks the caller's code-signing identity and validates every request. It
runs a watchdog that returns fan control to macOS when the app stops sending
heartbeats or the machine runs hot, and it exits when it detects that its own
executable was replaced so the new build is picked up.

## Consequences

- Privileged code is small and separately testable.
- Every new privileged feature adds a method to the protocol with its own validation
  and tests; the helper never executes caller-supplied commands.
- Installing the helper requires one-time user approval in System Settings.
