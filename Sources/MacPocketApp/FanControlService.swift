import AppKit
import Foundation
import MacPocketCore
import ServiceManagement

/// App side of fan control: registers the privileged helper, drives it over XPC and keeps its heartbeat alive.
/// Runs for as long as a manual profile is active, even when the Güç Merkezi page is closed.
@MainActor
final class FanControlService: ObservableObject {
    static let shared = FanControlService()

    enum Availability: Equatable {
        case notInstalled, needsApproval, ready
        case unavailable(String)
    }

    struct Fan: Equatable, Identifiable {
        let id: Int
        let rpm: Double
        let range: ClosedRange<Double>
    }

    /// The preset behind "Sıcaklığa göre": quiet until the machine warms up, full speed near the limit.
    static let temperatureCurve = FanProfile.curve([
        CurvePoint(celsius: 45, percent: 0), CurvePoint(celsius: 60, percent: 35),
        CurvePoint(celsius: 75, percent: 75), CurvePoint(celsius: 85, percent: 100),
    ])

    private static let profileKey = "MacPocket.fan.profile"
    private static let tickSeconds = 2.0
    /// A new target is only sent when it differs this much from the last one, so the fans don't chase noise.
    private static let minimumStepRPM = 50.0

    @Published private(set) var availability: Availability = .notInstalled
    @Published private(set) var fans: [Fan] = []
    @Published private(set) var message: String?
    @Published var profile: FanProfile {
        didSet {
            guard profile != oldValue else { return }
            if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.profileKey) }
            curveState = FanCurveState()
            if profile == .system, !lastTargets.isEmpty { releasePending = true }
            lastTargets = [:]
            start()
        }
    }

    private let daemon = SMAppService.daemon(plistName: MacPocketHelperConstants.daemonPlistName)
    private let temperatures = HottestTemperatureReader()
    private var connection: NSXPCConnection?
    private var curveState = FanCurveState()
    private var lastTargets: [Int: Double] = [:]
    private var loop: Task<Void, Never>?
    private var visibleCount = 0
    /// Set when the user switched back to the system profile while fans were manual.
    private var releasePending = false

    private init() {
        profile = UserDefaults.standard.data(forKey: Self.profileKey)
            .flatMap { try? JSONDecoder().decode(FanProfile.self, from: $0) } ?? .system
        refreshAvailability()
        if profile != .system { start() }
    }

    /// True when this Mac has fans the helper can see; the card hides itself otherwise.
    var hasFans: Bool { !fans.isEmpty }

    // MARK: Helper lifecycle

    func refreshAvailability() {
        switch daemon.status {
        // `notFound` also covers a bundle launchd hasn't looked at yet; registering reports the real reason.
        case .notRegistered, .notFound: if !isUnavailable { availability = .notInstalled }
        case .requiresApproval: availability = .needsApproval
        case .enabled: if availability != .ready { availability = .ready }
        @unknown default: availability = .unavailable(String(localized: "Yardımcının durumu bilinmiyor."))
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = availability { return true }
        return false
    }

    func installHelper() {
        if daemon.status == .enabled { refreshAvailability(); return }
        do { try daemon.register() } catch {
            refreshAvailability()
            if daemon.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            // launchd refuses unsigned or ad-hoc builds; say so instead of offering controls that can't work.
            availability = .unavailable(String(localized: "Yardımcı servis kaydedilemedi: \(error.localizedDescription) Bu özellik yalnızca imzalı sürümde çalışır."))
            return
        }
        refreshAvailability()
        if availability == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Installation and authorization belong to the wizard; scans only reuse that service.
    func prepareNetworkHelper() throws {
        refreshAvailability()
        guard daemon.status == .enabled else {
            throw NSError(domain: "MacPocket.Helper", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Kurulum sihirbazındaki yardımcı servis şu anda etkin değil. Servis durumunu kurulum ekranından kontrol et.")])
        }
    }

    #if DEBUG
    /// Repairs an installation whose identity was changed during development, without opening another approval UI.
    func restoreWizardRegistration() async throws {
        // Remove only the accidentally renamed registration; retain the wizard's original service.
        try? await SMAppService.daemon(plistName: "com.doancan.MacPocket.Helper.plist").unregister()
        if daemon.status == .notRegistered || daemon.status == .notFound { try daemon.register() }
        refreshAvailability()
    }
    #endif

    func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: Visibility and loop

    func viewAppeared() { visibleCount += 1; start() }

    func viewDisappeared() {
        visibleCount = max(0, visibleCount - 1)
        if visibleCount == 0, profile == .system { loop?.cancel(); loop = nil }
    }

    private func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
            }
        }
    }

    private func tick() async {
        refreshAvailability()
        guard availability == .ready else { fans = []; return }
        guard let helper = proxy() else { return }
        let reading = await withCheckedContinuation { (continuation: CheckedContinuation<[Fan]?, Never>) in
            helper.status { values, error in
                guard error == nil else { continuation.resume(returning: nil); return }
                let fans = values.enumerated().compactMap { index, value -> Fan? in
                    guard value.count == 3 else { return nil }
                    return Fan(id: index, rpm: value[0].doubleValue, range: value[1].doubleValue...value[2].doubleValue)
                }
                continuation.resume(returning: fans)
            }
        }
        guard let reading else { return }
        fans = reading
        await apply(to: reading, helper: helper)
    }

    private func apply(to fans: [Fan], helper: MacPocketHelperXPC) async {
        let temperature = temperatures.celsius()
        // Profiles that depend on temperature must never run blind.
        if case .curve = profile, temperature == nil {
            message = String(localized: "Sıcaklık okunamadığı için fanlar sistemde bırakıldı.")
            await release(helper)
            return
        }
        if releasePending {
            releasePending = false
            await release(helper)
        }
        for fan in fans {
            guard let target = curveState.targetRPM(profile: profile, temperature: temperature ?? 0, range: fan.range) else {
                if lastTargets[fan.id] != nil { await release(helper) }
                message = nil
                return
            }
            if let last = lastTargets[fan.id], abs(last - target) < Self.minimumStepRPM {
                await heartbeat(helper)
                continue
            }
            let failure = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                helper.setTarget(fan: fan.id, rpm: target) { continuation.resume(returning: $0) }
            }
            if let failure {
                message = String(localized: "Fan hızı ayarlanamadı; sistem denetimine bırakıldı. (\(failure))")
                profile = .system
                return
            }
            lastTargets[fan.id] = target
            message = nil
        }
    }

    private func heartbeat(_ helper: MacPocketHelperXPC) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in helper.heartbeat { continuation.resume() } }
    }

    private func release(_ helper: MacPocketHelperXPC) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in helper.releaseAll { continuation.resume() } }
        lastTargets = [:]
    }

    private func proxy() -> MacPocketHelperXPC? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: MacPocketHelperConstants.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: MacPocketHelperXPC.self)
            connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.message = error.localizedDescription }
        } as? MacPocketHelperXPC
    }
}
