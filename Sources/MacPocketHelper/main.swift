import Foundation
import MacPocketCore
import OSLog
import Security

/// MacPocket's privileged helper, installed once (setup wizard or Güç Merkezi). Owns fan control and LAN MAC
/// discovery: the SMC writes, its own check of every request, and handing the fans back to macOS when the app
/// stops talking to it or the machine runs hot. Future privileged features belong here too, each validating
/// its own input.
final class MacPocketHelperService: NSObject, MacPocketHelperXPC, NSXPCListenerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacPocket.Helper")
    private let controller: FanController?
    private let networkQueue = DispatchQueue(label: "MacPocket.Helper.network")
    private var networkScan: Task<Void, Never>?
    private let temperatures = HottestTemperatureReader()
    private var thermalGuard = ThermalGuard()
    private var lastHeartbeat = Date()
    private var manual = false
    private var watchdog: DispatchSourceTimer?
    private let replacement: ExecutableReplacementCheck?
    private let logger = Logger(subsystem: "com.doancan.MacPocket.FanHelper", category: "Lifecycle")

    init(controller: FanController?) {
        self.controller = controller
        do { replacement = try ExecutableReplacementCheck.currentProcess() } catch {
            replacement = nil
            logger.error("Can't watch the helper executable for updates: \(error.localizedDescription, privacy: .public)")
        }
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
        watchdog = timer
    }

    // MARK: Safety

    private func watchdogTick() {
        // launchd never stops an on-demand helper, so after an app update this process would keep the old
        // code and the old client requirement until restart. Exiting hands the fans back; the next request
        // starts the new build.
        if replacement?.isReplaced == true {
            logger.notice("Helper executable was replaced; exiting so launchd starts the updated one")
            releaseNow()
            exit(0)
        }
        guard manual else { return }
        if Date().timeIntervalSince(lastHeartbeat) > MacPocketHelperConstants.heartbeatTimeout { releaseNow() }
        else if !thermalGuard.allowsManual(reading: temperatures.celsius()) { releaseNow() }
    }

    /// Stays in manual mode when a release fails, so the next watchdog tick tries again.
    private func releaseNow() {
        manual = controller?.releaseAll() == false
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MacPocketHelperXPC.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.queue.async { self.releaseNow() }
        }
        connection.resume()
        return true
    }

    // MARK: MacPocketHelperXPC

    func status(reply: @escaping @Sendable ([[NSNumber]], String?) -> Void) {
        queue.async {
            do {
                guard let controller = self.controller else { throw FanControlError.keyMissing("AppleSMC") }
                let fans = try (0..<controller.fanCount).map { fan -> [NSNumber] in
                    let range = try controller.range(fan: fan)
                    return [NSNumber(value: try controller.actualRPM(fan: fan) ?? 0),
                            NSNumber(value: range.lowerBound), NSNumber(value: range.upperBound)]
                }
                reply(fans, nil)
            } catch { reply([], "\(error)") }
        }
    }

    func setTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do {
                guard let controller = self.controller else { throw FanControlError.keyMissing("AppleSMC") }
                let ranges = try (0..<controller.fanCount).map { try controller.range(fan: $0) }
                try FanRequestValidator(fans: ranges).validate(fan: fan, rpm: rpm)
                // Without a readable temperature the guard can't protect the machine, so manual speeds are
                // refused.
                guard let hottest = self.temperatures.celsius() else { throw FanControlError.keyMissing("temperature") }
                guard self.thermalGuard.allowsManual(hottestCelsius: hottest) else { throw FanControlError.writeRefused("thermal") }
                try controller.setTarget(fan: fan, rpm: rpm)
                self.manual = true
                self.lastHeartbeat = Date()
                reply(nil)
            } catch {
                // A failed first request can leave the diagnostic unlock set with nothing supervising it.
                if !self.manual { self.controller?.releaseAll() }
                reply("\(error)")
            }
        }
    }

    func heartbeat(reply: @escaping @Sendable () -> Void) {
        queue.async { self.lastHeartbeat = Date(); reply() }
    }

    func releaseAll(reply: @escaping @Sendable () -> Void) {
        queue.async { self.releaseNow(); reply() }
    }

    func scanMACAddresses(cidr: String, interface: String, reply: @escaping @Sendable ([String: String], String?) -> Void) {
        // Serialize temporary routes without blocking the fan heartbeat or thermal watchdog queue.
        networkQueue.async {
            let previous = self.networkScan
            self.networkScan = Task {
                await previous?.value
                do {
                    let request = try LANHelperScanRequest(cidr: cidr, interface: interface)
                    reply(try await request.run(), nil)
                } catch { reply([:], error.localizedDescription) }
            }
        }
    }
}

/// Who may talk to the helper. A signed helper only accepts a MacPocket signed by the same Apple team, so
/// another app can't claim the identifier. An ad-hoc development build has no team to pin to and falls back
/// to the identifier alone; that is acceptable only because such a build can't be distributed.
func clientRequirement() -> String {
    let identifier = "identifier \"com.doancan.MacPocket\""
    // Any local process can sign itself with this identifier, so the fallback is logged at fault level: it
    // must never be the state of a distributed build.
    func identifierOnly(_ reason: String) -> String {
        Logger(subsystem: "com.doancan.MacPocket.FanHelper", category: "Security")
            .fault("Client requirement falls back to the identifier alone: \(reason, privacy: .public)")
        return identifier
    }
    var code: SecCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return identifierOnly("own code object unavailable") }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
    else { return identifierOnly("helper has no signing team") }
    return "anchor apple generic and \(identifier) and certificate leaf[subject.OU] = \"\(team)\""
}

// Network discovery remains available even on hardware without an accessible SMC.
let controller = AppleSMCTransport().map { FanController(transport: $0) }
let service = MacPocketHelperService(controller: controller)
let listener = NSXPCListener(machServiceName: MacPocketHelperConstants.machServiceName)
listener.delegate = service
listener.setConnectionCodeSigningRequirement(clientRequirement())

nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { controller?.releaseAll(); exit(0) }
    source.resume()
    signalSources.append(source)
}
listener.resume()
RunLoop.main.run()
