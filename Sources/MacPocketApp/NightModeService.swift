import AppKit
import Combine
import CoreLocation
import IOKit.pwr_mgt
import MacPocketCore

/// Night mode for the "follow the sun" schedule: dims every external display relative to its own day level and
/// warms the colour (MacPocket's gamma warmth or macOS Night Shift) along the sunset/sunrise curve, lifting both
/// while one of the optional exceptions applies.
///
/// Brightness is held while a manual change or a focus session wins (`DisplayBrightnessService.brightnessHeld`);
/// colour keeps following the curve.
@MainActor
final class NightModeService: ObservableObject {
    static let shared = NightModeService()
    nonisolated static let nightShiftSnapshotKey = "MacPocket.night.nightShiftSnapshot"
    /// `defaults write com.doancan.MacPocket MacPocket.night.debugNow -string "2026-11-02T18:00:00+03:00"`
    nonisolated static let debugNowKey = "MacPocket.night.debugNow"

    enum Status: Equatable {
        case off
        case needsLocation
        case active(NightTarget)
        case paused(until: Date?)
    }

    @Published private(set) var status: Status = .off

    /// What one evaluation wants applied. `multiplier` nil: brightness is not driven; `nightShift` nil: Night Shift off.
    private struct Plan {
        var multiplier: Double?
        var kelvin: Double
        var nightShift: Double?
    }

    private static let neutralKelvin = 6500.0
    private static let rampSteps = 8
    private static let rampStep = Duration.milliseconds(250)

    private let brightness = DisplayBrightnessService.shared
    /// Location for the sunrise/sunset times; the page observes its authorization.
    let location = NightLocationProvider()
    private let nightShiftClient: NightShiftClient
    private let nightShift: NightShiftSession
    private var started = false
    private var stopped = false
    private var timer: Timer?
    private var ramp: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var locationRequested = false

    /// Whether the last evaluation drove brightness (so turning that off returns the displays to their base).
    private var drivingBrightness = false
    /// The warmth last written with `setWarmth`, and to which displays.
    private var appliedKelvin = NightModeService.neutralKelvin
    private var warmthDisplays: Set<CGDirectDisplayID> = []
    /// Night Shift strength while the session is active.
    private var nightShiftStrength: Double?
    /// The level night mode last wrote (or accepted) per display key, to notice changes made elsewhere.
    private var lastApplied: [String: Double] = [:]
    /// The night amount actually in effect at the last evaluation (0 when paused or off).
    private var effectiveNight = 0.0

    private init() {
        let client = NightShiftClient()
        nightShiftClient = client
        nightShift = NightShiftSession(client: client, load: NightModeService.loadSnapshot, save: NightModeService.saveSnapshot)
    }

    /// Whether macOS Night Shift can be driven on this Mac.
    var nightShiftAvailable: Bool { nightShiftClient.isAvailable }

    /// The debug clock when set, otherwise the real time.
    var debugNow: Date? {
        UserDefaults.standard.string(forKey: Self.debugNowKey).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private var now: Date { debugNow ?? Date() }

    func start() {
        guard !started else { return }
        started = true
        // A snapshot left by a crash is the user's own Night Shift state: put it back before anything else.
        nightShift.recoverIfNeeded()
        brightness.solarManualChange = { [weak self] key, level in self?.manualLevelChanged(key: key, level: level) }
        location.onLocation = { [weak self] coordinate, name in
            self?.updateNight {
                $0.location = coordinate
                $0.locationName = name
            }
        }
        brightness.$settings.map(\.schedule).removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.locationRequested = false
                self?.evaluate()
            }
        }.store(in: &subscriptions)
        brightness.$displays.map { $0.map(\.id) }.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        evaluate()
    }

    func pauseForAnHour() {
        let until = now.addingTimeInterval(3600)
        updateNight { $0.pausedUntil = until }
        evaluate()
    }

    func resume() {
        updateNight { $0.pausedUntil = nil }
        evaluate()
    }

    /// "Use my location": asks for a fresh location now, even if one was fetched earlier today.
    func useCurrentLocation() {
        location.request(force: true)
    }

    /// Hands Night Shift back to the user and drops the warmth (software dimming is restored by the brightness service).
    func prepareForQuit() {
        stopped = true
        ramp?.cancel()
        timer?.invalidate()
        nightShift.deactivate()
        nightShiftStrength = nil
        if appliedKelvin < Self.neutralKelvin { brightness.setWarmth((1, 1, 1)) }
        appliedKelvin = Self.neutralKelvin
    }

    // MARK: Evaluation

    func evaluate() {
        guard started, !stopped else { return }
        timer?.invalidate()
        timer = nil
        let now = self.now
        let schedule = brightness.schedule
        guard schedule.enabled, schedule.source == .solar else {
            release(now: now)
            setStatus(.off)
            return
        }
        var settings = schedule.night ?? NightSettings()
        guard let coordinate = settings.location else {
            release(now: now)
            setStatus(.needsLocation)
            requestLocationIfAllowed()
            return
        }
        settings.nightLevel = min(max(settings.nightLevel, 0), 1)
        settings.nightKelvin = min(max(settings.nightKelvin, 1900), Self.neutralKelvin)
        let day = SolarCalculator.day(containing: now, at: coordinate, timeZone: .current)
        let target = NightCurve.target(at: now, day: day, settings: settings)
        let front = NSWorkspace.shared.frontmostApplication
        let video = settings.pauseForFullScreenVideo && front.map { Self.isPlayingFullScreenVideo(pid: $0.processIdentifier) } == true
        let paused = NightPause.isPaused(now: now, settings: settings, frontmostBundleID: front?.bundleIdentifier, fullScreenVideo: video)
        let night = paused ? 0 : target.night
        effectiveNight = night
        let warm = settings.warmColor && night > 0
        apply(Plan(multiplier: settings.dimBrightness ? (paused ? 1 : target.level) : nil,
                   kelvin: warm && settings.colorMethod == .macPocket ? target.kelvin : Self.neutralKelvin,
                   nightShift: warm && settings.colorMethod == .nightShift ? NightShiftStrength.from(kelvin: target.kelvin) : nil),
              baseLevels: settings.baseLevels, now: now)
        let pausedUntil = settings.pausedUntil.flatMap { $0 > now ? $0 : nil }
        setStatus(paused ? .paused(until: pausedUntil) : .active(target))

        var interval: TimeInterval = target.night > 0 && target.night < 1 ? 15 : 60
        if let pausedUntil { interval = min(interval, max(pausedUntil.timeIntervalSince(now), 1)) }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.evaluate() } }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Night mode is off: displays back to their base, warmth neutral, Night Shift handed back.
    private func release(now: Date) {
        effectiveNight = 0
        // Switched to the manual points: they already set the levels, so leave brightness to them.
        if brightness.schedule.enabled, brightness.schedule.source != .solar { drivingBrightness = false }
        apply(Plan(multiplier: nil, kelvin: Self.neutralKelvin, nightShift: nil),
              baseLevels: brightness.schedule.night?.baseLevels ?? [:], now: now)
    }

    private func setStatus(_ new: Status) {
        if status != new { status = new }
    }

    // MARK: Applying

    private struct Move {
        let id: CGDirectDisplayID
        let key: String
        let hardware: Bool
        let from: Double
        let to: Double
    }

    /// Small changes (the curve's own 15 s steps) are written at once; larger ones (an exception starting or ending,
    /// launch, settings) ramp over ~2 s. DDC displays take a ramp's final level in one write.
    private func apply(_ plan: Plan, baseLevels: [String: Double], now: Date) {
        ramp?.cancel()
        ramp = nil
        applyNightShift(plan.nightShift)

        var moves: [Move] = []
        let driveBrightness = plan.multiplier != nil || drivingBrightness
        drivingBrightness = plan.multiplier != nil
        if driveBrightness {
            if brightness.brightnessHeld(at: now) {
                // Whatever the user or the focus session set is accepted as ours, so it isn't mistaken for a new base.
                for display in brightness.displays { lastApplied[display.key] = display.level }
            } else {
                let bases = resolveBases(baseLevels)
                for display in brightness.displays {
                    let to = min(1, max(0, (bases[display.key] ?? display.level) * (plan.multiplier ?? 1)))
                    if abs(display.level - to) > 0.01 {
                        moves.append(Move(id: display.id, key: display.key, hardware: display.active == .hardware,
                                          from: display.level, to: to))
                    } else {
                        lastApplied[display.key] = display.level
                    }
                }
            }
        }

        let ids = Set(brightness.displays.map(\.id))
        let fromKelvin = appliedKelvin
        let toKelvin = plan.kelvin
        let warmthNeeded = abs(toKelvin - fromKelvin) > 0.5 || (toKelvin < Self.neutralKelvin && ids != warmthDisplays)
        let large = abs(toKelvin - fromKelvin) > 300 || moves.contains { abs($0.to - $0.from) > 0.05 }

        func step(_ fraction: Double, hardware: Bool) {
            for move in moves where move.hardware == hardware {
                let level = move.from + (move.to - move.from) * fraction
                brightness.setLevel(level, for: move.id, fromSchedule: true)
                lastApplied[move.key] = level
            }
            guard !hardware, warmthNeeded else { return }
            let kelvin = fromKelvin + (toKelvin - fromKelvin) * fraction
            let f = ColorTemperature.channelFactors(kelvin: kelvin)
            brightness.setWarmth((f.red, f.green, f.blue))
            appliedKelvin = kelvin
            warmthDisplays = ids
        }

        step(1, hardware: true)
        guard large else {
            step(1, hardware: false)
            return
        }
        step(1 / Double(Self.rampSteps), hardware: false)
        ramp = Task {
            for index in 2...Self.rampSteps {
                try? await Task.sleep(for: Self.rampStep)
                guard !Task.isCancelled else { return }
                step(Double(index) / Double(Self.rampSteps), hardware: false)
            }
        }
    }

    /// Each display's day level: the stored base, or its current level the first time night mode sees it. During the
    /// day (and while paused) a level changed outside MacPocket's own writes, e.g. on the monitor, becomes the base.
    private func resolveBases(_ stored: [String: Double]) -> [String: Double] {
        var bases = stored
        for display in brightness.displays {
            if bases[display.key] == nil {
                bases[display.key] = display.level
            } else if effectiveNight == 0, let last = lastApplied[display.key], abs(display.level - last) > 0.02 {
                bases[display.key] = display.level
            }
        }
        if bases != stored { updateNight { $0.baseLevels = bases } }
        return bases
    }

    private func applyNightShift(_ strength: Double?) {
        if let strength {
            // Every activate writes the strength; skip changes too small to see.
            if let current = nightShiftStrength, abs(current - strength) < 0.01 { return }
            nightShift.activate(strength: strength)
            nightShiftStrength = strength
        } else if nightShiftStrength != nil {
            nightShift.deactivate()
            nightShiftStrength = nil
        }
    }

    // MARK: Manual changes

    /// A level set by the user in "follow the sun" mode. By day (or while paused) it becomes the display's base;
    /// at night or in a transition it holds brightness until the current or next transition ends.
    private func manualLevelChanged(key: String, level: Double) -> Date? {
        lastApplied[key] = level
        let settings = brightness.schedule.night ?? NightSettings()
        guard effectiveNight > 0, settings.dimBrightness, let coordinate = settings.location else {
            updateNight { $0.baseLevels[key] = level }
            return nil
        }
        let now = self.now
        let calendar = Calendar.current
        if let end = NightCurve.transitionEnd(after: now, day: SolarCalculator.day(containing: now, at: coordinate, timeZone: .current),
                                              settings: settings) {
            return end
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        // Polar day or night has no transition: hold until the next day instead of forever.
        return NightCurve.transitionEnd(after: now, day: SolarCalculator.day(containing: tomorrow, at: coordinate, timeZone: .current),
                                        settings: settings) ?? calendar.startOfDay(for: tomorrow)
    }

    // MARK: Helpers

    /// Writes into the stored night settings without the schedule setter's side effects (it clears manual holds).
    /// The change re-evaluates night mode through the settings subscription.
    func updateNight(_ change: (inout NightSettings) -> Void) {
        var schedule = brightness.schedule
        var night = schedule.night ?? NightSettings()
        change(&night)
        guard night != schedule.night else { return }
        schedule.night = night
        brightness.settings.schedule = schedule
    }

    private func requestLocationIfAllowed() {
        guard !locationRequested else { return }
        switch location.authorization {
        case .notDetermined, .authorizedAlways:
            locationRequested = true
            location.request()
        default:
            break
        }
    }

    /// Full-screen video: the front app has a normal-layer window covering a whole display, and that same process
    /// keeps the display awake (`PreventUserIdleDisplaySleep`).
    private static func isPlayingFullScreenVideo(pid: pid_t) -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let assertions = byProcess[NSNumber(value: pid)],
              assertions.contains(where: {
                  let type = $0[kIOPMAssertionTypeKey] as? String
                  return type == kIOPMAssertionTypePreventUserIdleDisplaySleep || type == "NoDisplaySleepAssertion"
              }) else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return false }
        let screens = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return screens.contains { $0 == rect }
        }
    }

    private nonisolated static func loadSnapshot() -> NightShiftState? {
        UserDefaults.standard.data(forKey: nightShiftSnapshotKey).flatMap { try? JSONDecoder().decode(NightShiftState.self, from: $0) }
    }

    private nonisolated static func saveSnapshot(_ state: NightShiftState?) {
        if let state, let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: nightShiftSnapshotKey)
        } else {
            UserDefaults.standard.removeObject(forKey: nightShiftSnapshotKey)
        }
    }
}
