import AppKit
import Foundation
import MacPocketCore
import ServiceManagement
import Synchronization

/// The helper's launchd registration; `SMAppService` in the app, a fixture in tests.
@MainActor
protocol HelperRegistration: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

extension SMAppService: HelperRegistration {}

/// App side of fan control: registers the privileged helper, drives it over XPC and keeps its heartbeat
/// alive. Runs for as long as a manual profile is active, even when the Güç Merkezi page is closed.
@MainActor
final class FanControlService: ObservableObject {
    static let shared = FanControlService()

    enum Availability: Equatable {
        case notInstalled, needsApproval, ready
        case unavailable(String)
    }

    /// Whether `fans` reflects an answer from the helper: an empty list only means "no fans" once it is
    /// `.loaded`.
    enum Reading: Equatable {
        case loading, failed, loaded
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
    @Published private(set) var reading: Reading = .loading
    @Published private(set) var message: String?
    @Published var profile: FanProfile {
        didSet {
            guard profile != oldValue else { return }
            if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.profileKey) }
            curveState = FanCurveState()
            if profile == .system { releasePending = true }
            lastTargets = [:]
            start()
        }
    }

    /// Returns a helper proxy. NSXPC calls `onError` on its own queue, never on the main actor.
    typealias HelperConnector = @MainActor (_ onError: @escaping @Sendable (any Error) -> Void) -> (any MacPocketHelperXPC)?

    private let daemon: any HelperRegistration
    private let openLoginItems: () -> Void
    /// launchd queues messages for a helper it can't start, so without a limit a request would wait forever.
    private let requestTimeout: Duration
    private let defaults: UserDefaults
    private let temperatures: any FanTemperatureReading
    private let helperOverride: (any MacPocketHelperXPC)?
    private let connectorOverride: HelperConnector?
    private var connection: NSXPCConnection?
    private var curveState = FanCurveState()
    private var lastTargets: [Int: Double] = [:]
    private var loop: Task<Void, Never>?
    private var loopGeneration = UUID()
    private var visibleCount = 0
    /// Set when the user switched back to the system profile while fans were manual.
    private var releasePending = false

    init(defaults: UserDefaults = .standard, temperatures: any FanTemperatureReading = FanTemperatureReader(),
         helper: (any MacPocketHelperXPC)? = nil, connector: HelperConnector? = nil,
         registration: any HelperRegistration = SMAppService.daemon(plistName: MacPocketHelperConstants.daemonPlistName),
         openLoginItems: @escaping () -> Void = SMAppService.openSystemSettingsLoginItems,
         requestTimeout: Duration = .seconds(10)) {
        self.requestTimeout = requestTimeout
        self.defaults = defaults
        daemon = registration
        self.openLoginItems = openLoginItems
        self.temperatures = temperatures
        helperOverride = helper
        connectorOverride = connector
        profile = defaults.data(forKey: Self.profileKey)
            .flatMap { try? JSONDecoder().decode(FanProfile.self, from: $0) } ?? .system
        refreshAvailability()
        if profile != .system { start() }
    }

    /// True when this Mac has fans the helper can see; the card hides itself otherwise.
    var hasFans: Bool { !fans.isEmpty }

    // MARK: Helper lifecycle

    func refreshAvailability() {
        if helperOverride != nil || connectorOverride != nil { availability = .ready; return }
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
                openLoginItems()
                return
            }
            // launchd refuses unsigned or ad-hoc builds; say so instead of offering controls that can't work.
            // The card shows this reason, so a warning left from an earlier attempt would only contradict it.
            message = nil
            availability = .unavailable(String(localized: "Yardımcı servis kaydedilemedi: \(error.localizedDescription) Bu özellik yalnızca imzalı sürümde çalışır."))
            return
        }
        refreshAvailability()
        if availability == .needsApproval { openLoginItems() }
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
    /// Repairs an installation whose identity was changed during development, without opening another
    /// approval UI.
    func restoreWizardRegistration() async throws {
        // Remove only the accidentally renamed registration; retain the wizard's original service.
        try? await SMAppService.daemon(plistName: "com.doancan.MacPocket.Helper.plist").unregister()
        if daemon.status == .notRegistered || daemon.status == .notFound { try daemon.register() }
        refreshAvailability()
    }
    #endif

    func openApproval() { openLoginItems() }

    /// For a helper that is registered but won't answer; e.g. its launch constraint still pins the signing
    /// team of the build that registered it, after switching between a release and a development build.
    /// Registering again ties it to this build; macOS asks for approval once more.
    func repairHelper() async {
        do { try await daemon.unregister() } catch {
            message = String(localized: "Yardımcı servis kaldırılamadı: \(error.localizedDescription)")
            return
        }
        reading = .loading
        lastTargets = [:]
        connection?.invalidate()
        connection = nil
        installHelper()
    }

    // MARK: Visibility and loop

    func viewAppeared() { visibleCount += 1; start() }

    func viewDisappeared() {
        visibleCount = max(0, visibleCount - 1)
        if !pollingWanted { loop?.cancel(); loop = nil }
    }

    private var pollingWanted: Bool { visibleCount > 0 || profile != .system || releasePending }
    var isPolling: Bool { loop != nil }

    private func start() {
        guard loop == nil, pollingWanted else { return }
        let generation = UUID()
        loopGeneration = generation
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                guard self.pollingWanted else { break }
                do { try await Task.sleep(for: .seconds(Self.tickSeconds)) } catch { break }
            }
            if let self, self.loopGeneration == generation { self.loop = nil }
        }
    }

    private func tick() async {
        refreshAvailability()
        guard availability == .ready else { fans = []; message = nil; return }
        await releaseIfPending()
        guard !Task.isCancelled, pollingWanted else { return }
        let reading: [Fan]? = await request(failure: nil) { helper, done in
            helper.status { values, error in
                guard error == nil else { done(nil); return }
                done(values.enumerated().compactMap { index, value -> Fan? in
                    guard value.count == 3 else { return nil }
                    return Fan(id: index, rpm: value[0].doubleValue, range: value[1].doubleValue...value[2].doubleValue)
                })
            }
        }
        guard !Task.isCancelled else { return }
        guard let reading else { self.reading = .failed; return }
        fans = reading
        self.reading = .loaded
        await apply(to: reading)
        await releaseIfPending()
    }

    private func apply(to fans: [Fan]) async {
        await releaseIfPending()
        guard !Task.isCancelled else { return }
        let selectedProfile = profile
        guard selectedProfile != .system else { message = nil; return }
        let temperature: Double?
        if case .curve = selectedProfile {
            temperature = await temperatures.celsius()
            guard !Task.isCancelled, profile == selectedProfile else { return }
            // Profiles that depend on temperature must never run blind.
            guard temperature != nil else {
                message = String(localized: "Sıcaklık okunamadığı için fanlar sistemde bırakıldı.")
                await release()
                return
            }
        } else { temperature = nil }
        for fan in fans {
            guard !Task.isCancelled, profile == selectedProfile else { return }
            guard let target = curveState.targetRPM(profile: selectedProfile, temperature: temperature ?? 0, range: fan.range) else {
                if lastTargets[fan.id] != nil { await release() }
                message = nil
                return
            }
            if let last = lastTargets[fan.id], abs(last - target) < Self.minimumStepRPM {
                await heartbeat()
                continue
            }
            let reply: TargetReply = await request(failure: .unreachable) { helper, done in
                helper.setTarget(fan: fan.id, rpm: target) { done($0.map(TargetReply.rejected) ?? .accepted) }
            }
            guard !Task.isCancelled else { return }
            guard profile == selectedProfile else { return }
            switch reply {
            case .accepted:
                lastTargets[fan.id] = target
                message = nil
            case .rejected(let failure):
                message = String(localized: "Fan hızı ayarlanamadı; sistem denetimine bırakıldı. (\(failure))")
                profile = .system
                return
            case .unreachable:
                // The error handler already reported it; the next tick retries, and the helper's
                // heartbeat timeout hands the fans back to the system if it stays unreachable.
                return
            }
        }
    }

    private func heartbeat() async {
        await request(failure: ()) { helper, done in helper.heartbeat { done(()) } }
    }

    private func release() async {
        await request(failure: ()) { helper, done in helper.releaseAll { done(()) } }
        lastTargets = [:]
    }

    private func releaseIfPending() async {
        guard releasePending else { return }
        releasePending = false
        await release()
    }

    private enum TargetReply: Sendable {
        case accepted, rejected(String), unreachable
    }

    /// NSXPC calls either the reply or the proxy's error handler, never both, and does so on its own queue.
    /// Whichever arrives first resumes the caller exactly once, so an unreachable helper can't stall the
    /// loop.
    private func request<Value: Sendable>(failure: Value,
                                          _ send: (any MacPocketHelperXPC, @escaping @Sendable (Value) -> Void) -> Void) async -> Value {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            let pending = PendingReply(continuation)
            let onError: @Sendable (any Error) -> Void = { [weak self] error in
                guard pending.finish(failure) else { return }
                Task { @MainActor in self?.message = error.localizedDescription }
            }
            guard let helper = proxy(onError: onError) else { pending.finish(failure); return }
            Task { [weak self, requestTimeout] in
                // Ends early only if the task is cancelled, which nothing does; a reply makes this a no-op.
                do { try await Task.sleep(for: requestTimeout) } catch { return }
                guard pending.finish(failure) else { return }
                self?.message = String(localized: "Yardımcı servis yanıt vermedi.")
            }
            send(helper) { pending.finish($0) }
        }
    }

    /// The helper went away (crashed, or restarted after an app update) and a new one starts with the fans
    /// under system control, so the next tick sends the manual targets again instead of only a heartbeat.
    func connectionLost() {
        connection = nil
        lastTargets = [:]
    }

    private func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any MacPocketHelperXPC)? {
        if let helperOverride { return helperOverride }
        if let connectorOverride { return connectorOverride(onError) }
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: MacPocketHelperConstants.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: MacPocketHelperXPC.self)
            connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connectionLost() } }
            connection.resume()
            self.connection = connection
        }
        // `onError` is typed @Sendable so it stays nonisolated; an inferred @MainActor closure traps here.
        return connection?.remoteObjectProxyWithErrorHandler(onError) as? MacPocketHelperXPC
    }
}

/// Resumes its continuation once; later replies or errors for the same request are ignored.
private final class PendingReply<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, Never>?>
    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = Mutex(continuation) }
    /// Returns whether this call ended the request; later replies, errors and timeouts are ignored.
    @discardableResult
    func finish(_ value: Value) -> Bool {
        guard let continuation = continuation.withLock({ $0.take() }) else { return false }
        continuation.resume(returning: value)
        return true
    }
}
