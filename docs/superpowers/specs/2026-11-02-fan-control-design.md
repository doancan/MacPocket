# Fan control (Güç Merkezi, step 2) — design

## Goal

Let the user set real fan speeds from MacPocket, safely, and show nothing that doesn't work. Reading RPM already exists (`FanSensors.swift`); this adds writing.

## What this Mac reports (read-only SMC dump, 2026-11-02)

- `FNum` = 2 fans. Per fan `F<n>`: `Ac` actual (flt), `Mn` min = 1100 RPM, `Mx` max = 3500 RPM, `Tg` target (flt, writable, attr `d4`), `Md` mode (ui8, writable, attr `d0`, currently 0 = system), `St` status, `Dc`/`Dz`/`CR` other.
- No `Ftst` key on this machine. Earlier Apple-silicon generations needed `Ftst=1` before `Md` accepted a write; this one may not. The writer therefore tries the key only when it exists and verifies by readback instead of assuming.
- Idle RPM sits near the minimum (~1320 / ~1350), so a change is visible.

## Architecture

1. **Core (`MacPocketCore`), pure and tested with a fake transport**
   - `SMCTransport` protocol: `readKey`, `writeKey`, `keyInfo`. The real one wraps the AppleSMC user client already used by `FanSensor`; tests use an in-memory fake.
   - `FanController`: `setTarget(fan:rpm:)` clamps to `[Mn, Mx]`, writes `Md=1` (and `Ftst` if present), writes `Tg`, reads `Ac` until it moves toward the target or times out, and throws a typed error on failure (key missing, write refused, no movement). `release(fan:)` writes `Md=0` (and `Ftst=0`). `releaseAll()` never throws past the first failure; it tries every fan.
   - `FanProfile` (value type): `.system`, `.fixed(percent)`, `.curve([(celsius, percent)])`. `FanProfile.targetRPM(temperature:range:)` is a pure function; the curve has hysteresis so the speed doesn't oscillate.
2. **Privileged helper (`MacPocketFanHelper`, new executable target)**
   - A LaunchDaemon registered with `SMAppService.daemon(plistName:)`, plist in `Contents/Library/LaunchDaemons`. Runs as root, exposes a small XPC interface: `status()`, `setTarget(fan, rpm)`, `releaseAll()`.
   - The helper accepts connections only from a client satisfying MacPocket's code-signing requirement, and validates every request again (fan index, RPM within the SMC-reported range). It never trusts the app's clamping.
   - **Dead-man's switch:** the app sends a heartbeat every 5 s while a manual profile is active. 15 s without one, or the connection dropping, makes the helper `releaseAll()`. App crash, quit, force-quit and sleep all end in system control.
   - **Thermal override:** if the hottest CPU/GPU sensor passes 90 °C the helper releases to system control and refuses new manual targets until it cools below 80 °C.
3. **App (`MacPocketApp`)**
   - `FanControlService` (`@MainActor`, `ObservableObject`): helper state (`notInstalled`, `needsApproval`, `ready`, `unavailable(reason)`), applies the active profile on each monitoring tick, sends heartbeats, releases on quit.
   - Power Center → new "Fanlar" card, shown only when `FNum > 0`. Not ready: one honest line with the reason and a single "Yardımcıyı etkinleştir" button (opens Login Items approval). Ready: per-fan RPM gauge plus profile picker (Sistem / Sabit / Eğri) and a slider clamped to the real range. Every control displays the value read back, not the value requested.
   - Everything user-visible is localized (Turkish source, English in `Localizable.strings`).

## Honest limits

- Registering a daemon needs a Developer ID–signed app in `/Applications` and the user's approval in System Settings. Ad-hoc dev builds may be refused by launchd; if so the card shows "Bu derleme imzasız; fan kontrolü yalnızca imzalı sürümde çalışır" and no fake controls. I'll find out in the implementation step and report it rather than assume.
- Live write verification needs root once. I'll ask you to run a one-line command with `!` while watching RPM; nothing is written to the SMC without your go-ahead, and the test ends with `Md=0`.
- Only the key layout observed on this Mac is supported. Different layouts (Intel `fpe2`, M5 renames) are detected by missing keys and reported as unsupported rather than guessed.

## Tests

- Core unit tests with the fake transport: clamping, key sequence with/without `Ftst`, readback failure → typed error and release, `releaseAll` continues after one failure, curve with hysteresis, thermal override.
- Helper request validation (out-of-range fan or RPM refused) as unit tests on the validator, independent of XPC.
- Manual/live: dump keys, approve helper, set 2000 RPM, confirm `F0Ac` follows via `smcdump`, quit the app and confirm RPM returns to system control.

## Out of scope

CPU management (step 3), profile automation by app/schedule (step 4), Intel Macs, fan control while on battery policy.
