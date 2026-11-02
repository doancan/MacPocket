# Fan Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Real, verified fan speed control from Güç Merkezi, with automatic release to system control.

**Architecture:** Pure logic and SMC access in `MacPocketCore` behind an `SMCTransport` protocol; a root LaunchDaemon (`MacPocketFanHelper`) performs writes over XPC and validates every request; the app drives it through `FanControlService` and shows a Fanlar card only when it works.

**Tech Stack:** Swift 6.4, IOKit AppleSMC, XPC (`NSXPCConnection`), `SMAppService.daemon`, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-02-fan-control-design.md`

## Global Constraints

- macOS 27 minimum; Turkish UI source with English in `Resources/en.lproj/Localizable.strings`; `scripts/check-localizations.sh` must report 0 missing.
- No SMC write without the user's go-ahead for the live test; every live test ends with `Md=0`.
- Never write below `Mn` or above `Mx`; helper re-validates independently of the app.
- No version/build changes, no commits unless asked, no AI signatures.

## Review Focus

- Fan count 0 (no fans): no Fanlar card, no errors.
- `Ftst` missing or present: key sequence differs, both tested.
- Write accepted but RPM never moves: typed error and release, UI shows failure not success.
- App killed mid-manual: helper releases within 15 s.
- Target outside `[Mn, Mx]` or fan index out of range: refused by the helper validator.

---

### Task 1: SMC transport and FanController (Core)

**Files:** Create `Sources/MacPocketCore/FanController.swift`, `Tests/MacPocketCoreTests/FanControllerTests.swift`.

**Interfaces:**
- Produces: `protocol SMCTransport { func read(_ key: String) throws -> SMCKeyValue?; func write(_ key: String, bytes: [UInt8]) throws }`, `struct SMCKeyValue { type: String; bytes: [UInt8] }`, `enum FanControlError: Error, Equatable { noSuchFan, keyMissing(String), writeRefused(String), noMovement(fan: Int) }`, `final class FanController { init(transport:); func setTarget(fan: Int, rpm: Double) throws; func release(fan: Int) throws; func releaseAll() }`.

- [ ] Test `testSetTargetClampsToRange`: fake transport with `F0Mn=1100`, `F0Mx=3500`; `setTarget(fan:0, rpm: 100)` writes `F0Tg` = 1100.0 (flt little-endian), `rpm: 9000` writes 3500.0.
- [ ] Test `testWritesModeThenTargetWithoutFtst`: write order is `F0Md=1`, `F0Tg`; no `Ftst` write when the key is absent.
- [ ] Test `testWritesFtstFirstWhenPresent`: order is `Ftst=1`, `F0Md=1`, `F0Tg`.
- [ ] Test `testNoMovementReleasesAndThrows`: fake `F0Ac` stays put → `noMovement(fan:0)` and `F0Md=0` written.
- [ ] Test `testReleaseAllContinuesAfterFailure`: first fan's write throws; second fan still released.
- [ ] Implement `FanController` (flt encode via `Float.bitPattern`, little-endian; poll `Ac` up to 5 s in 0.25 s steps through an injectable `sleep` closure so tests don't wait).
- [ ] Run `swift test --filter FanControllerTests` → pass.

### Task 2: Real transport and read-only probe

**Files:** Modify `Sources/MacPocketCore/FanSensors.swift` (extract the AppleSMC struct call into `AppleSMCTransport: SMCTransport`, add write via command 6, `FanSensor` uses it), `Sources/MacPocketProbe/MacPocketProbe.swift` (add `fans` command printing keys read-only).

- [ ] Move `Parameters`/`call` into `AppleSMCTransport`; `FanSensor` behavior unchanged (existing tests stay green).
- [ ] `macpocket-probe fans` prints per-fan `Ac/Mn/Mx/Md/Tg`; run it and compare with the smcdump values (1100/3500, mode 0).
- [ ] `swift test` full pass.

### Task 3: FanProfile curve (Core)

**Files:** Create `Sources/MacPocketCore/FanProfile.swift`, `Tests/MacPocketCoreTests/FanProfileTests.swift`.

**Interfaces:** `enum FanProfile: Codable, Equatable { case system; case fixed(percent: Double); case curve([CurvePoint]) }`, `struct CurvePoint { celsius: Double; percent: Double }`, `struct FanCurveState { mutating func targetRPM(profile:temperature:range:) -> Double? }` (nil = system control).

- [ ] Tests: `.system` → nil; `.fixed(50)` on 1100…3500 → 2300; curve interpolates linearly between points and clamps at ends; hysteresis: a 1 °C dip does not lower the target until 3 °C below the last step.
- [ ] Implement; run filter tests.

### Task 4: Request validator and XPC contract (Core)

**Files:** Create `Sources/MacPocketCore/FanHelperProtocol.swift`, `Tests/MacPocketCoreTests/FanRequestValidatorTests.swift`.

**Interfaces:** `@objc protocol FanHelperXPC { status(reply:), setTarget(fan:rpm:reply:), heartbeat(reply:), releaseAll(reply:) }`, `struct FanRequestValidator { init(fans: [FanRange]); func validate(fan: Int, rpm: Double) throws }`, `struct ThermalGuard { mutating func allowsManual(hottestCelsius: Double) -> Bool }` (trip 90 °C, resume below 80 °C).

- [ ] Tests: fan index out of range, NaN, below `Mn`, above `Mx` rejected; boundaries accepted; guard trips at 90, stays tripped at 85, clears at 79.
- [ ] Implement; run filter tests.

### Task 5: Helper executable and packaging

**Files:** Create `Sources/MacPocketFanHelper/main.swift`, `Resources/Daemons/com.doancan.MacPocket.FanHelper.plist`; modify `Package.swift`, `scripts/build-app.sh`.

- [ ] Helper: listener with code-signing requirement for MacPocket, uses `FanController` + validator + `ThermalGuard`; dead-man's switch (15 s without heartbeat or connection invalidated → `releaseAll`); releases on SIGTERM.
- [ ] `build-app.sh` copies the helper to `Contents/MacOS` and plist to `Contents/Library/LaunchDaemons`, signs both.
- [ ] Build the app bundle; inspect with `codesign -dv` and `plutil -lint`.

### Task 6: App service and UI

**Files:** Create `Sources/MacPocketApp/FanControlService.swift`, `Sources/MacPocketApp/FanControlCard.swift`; modify `PowerManagementView.swift` (card in Genel Bakış), `Resources/en.lproj/Localizable.strings`.

- [ ] Service states `notInstalled / needsApproval / ready / unavailable(reason)` from `SMAppService.daemon(plistName:).status`; heartbeat every 5 s while a manual profile is active; release on `applicationWillTerminate`.
- [ ] Card shown only when `FNum > 0`; not ready → one reason line plus "Yardımcıyı etkinleştir" (opens Login Items); ready → profile picker, slider within the real range, displays read-back RPM.
- [ ] `check-localizations.sh` → 0 missing; full `swift test`.

### Task 7: Live verification (needs the user)

- [ ] Ask the user to approve the helper in System Settings; confirm `status` is ready.
- [ ] With the user's go-ahead: set 2000 RPM, read `F0Ac` with `smcdump` until it follows; report numbers.
- [ ] Kill the app; confirm RPM returns to system control within 15 s and `F0Md=0`.
- [ ] If launchd refuses the ad-hoc build, record that and show the "imzasız derleme" state instead of fake controls.
