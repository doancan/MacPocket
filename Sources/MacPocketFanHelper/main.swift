import Foundation
import MacPocketCore
import Security

/// Root helper behind Güç Merkezi's fan control. It owns the SMC writes, checks every request itself, and
/// gives the fans back to macOS when the app stops talking to it or the machine runs hot.
final class FanHelperService: NSObject, FanHelperXPC, NSXPCListenerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacPocket.FanHelper")
    private let controller: FanController
    private let temperatures = HottestTemperatureReader()
    private var thermalGuard = ThermalGuard()
    private var lastHeartbeat = Date()
    private var manual = false
    private var watchdog: DispatchSourceTimer?

    init(controller: FanController) {
        self.controller = controller
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
        watchdog = timer
    }

    // MARK: Safety

    private func watchdogTick() {
        guard manual else { return }
        if Date().timeIntervalSince(lastHeartbeat) > FanHelperConstants.heartbeatTimeout { releaseNow() }
        else if let hottest = temperatures.celsius(), !thermalGuard.allowsManual(hottestCelsius: hottest) { releaseNow() }
    }

    private func releaseNow() {
        controller.releaseAll()
        manual = false
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.queue.async { self.releaseNow() }
        }
        connection.resume()
        return true
    }

    // MARK: FanHelperXPC

    func status(reply: @escaping @Sendable ([[NSNumber]], String?) -> Void) {
        queue.async {
            do {
                let fans = try (0..<self.controller.fanCount).map { fan -> [NSNumber] in
                    let range = try self.controller.range(fan: fan)
                    return [NSNumber(value: try self.controller.actualRPM(fan: fan) ?? 0),
                            NSNumber(value: range.lowerBound), NSNumber(value: range.upperBound)]
                }
                reply(fans, nil)
            } catch { reply([], "\(error)") }
        }
    }

    func setTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do {
                let ranges = try (0..<self.controller.fanCount).map { try self.controller.range(fan: $0) }
                try FanRequestValidator(fans: ranges).validate(fan: fan, rpm: rpm)
                // Without a readable temperature the guard can't protect the machine, so manual speeds are refused.
                guard let hottest = self.temperatures.celsius() else { throw FanControlError.keyMissing("temperature") }
                guard self.thermalGuard.allowsManual(hottestCelsius: hottest) else { throw FanControlError.writeRefused("thermal") }
                try self.controller.setTarget(fan: fan, rpm: rpm)
                self.manual = true
                self.lastHeartbeat = Date()
                reply(nil)
            } catch { reply("\(error)") }
        }
    }

    func heartbeat(reply: @escaping @Sendable () -> Void) {
        queue.async { self.lastHeartbeat = Date(); reply() }
    }

    func releaseAll(reply: @escaping @Sendable () -> Void) {
        queue.async { self.releaseNow(); reply() }
    }
}

/// Who may talk to the helper. A properly signed helper only accepts a MacPocket signed by the same Apple team,
/// so another app can't claim the identifier. An ad-hoc development build has no team to pin to and falls back
/// to the identifier alone; that is acceptable only because such a build can't be distributed.
func clientRequirement() -> String {
    let identifier = "identifier \"com.doancan.MacPocket\""
    var code: SecCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return identifier }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
    else { return identifier }
    return "anchor apple generic and \(identifier) and certificate leaf[subject.OU] = \"\(team)\""
}

guard let transport = AppleSMCTransport() else {
    FileHandle.standardError.write(Data("AppleSMC is not reachable\n".utf8))
    exit(1)
}
let controller = FanController(transport: transport)
let service = FanHelperService(controller: controller)
let listener = NSXPCListener(machServiceName: FanHelperConstants.machServiceName)
listener.delegate = service
listener.setConnectionCodeSigningRequirement(clientRequirement())

nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { controller.releaseAll(); exit(0) }
    source.resume()
    signalSources.append(source)
}
listener.resume()
RunLoop.main.run()
