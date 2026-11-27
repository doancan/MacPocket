#if DEBUG
import AppKit
import Darwin
import MacPocketCore
import ScreenCaptureKit
import SwiftUI

/// Isolated fixture UI plus read-only live hardware and an owned loopback TCP connection.
@MainActor enum CableImpactRuntimeAudit {
    static var requested: Bool { CommandLine.arguments.contains("--audit-cable-impact") }
    static func configureIfRequested() {
        guard requested else { return }
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        values[PocketPreferenceKey.showWindowAtLaunch] = false
        for module in PocketModule.allCases { values[module.availabilityKey] = false }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }
    static func launch() {
        guard let index = CommandLine.arguments.firstIndex(of: "--audit-cable-impact"), CommandLine.arguments.indices.contains(index + 1) else { NSApp.terminate(nil); return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        Task { @MainActor in await run(directory: directory); NSApp.terminate(nil) }
    }
    private static func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
    private static func run(directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var checks: [String: Bool] = [:], details: [String: Any] = [:], failure: String?
        var window: NSWindow?
        do {
            let live = try await CableResourceReader.read()
            checks["liveInventoryRead"] = !live.nodes.isEmpty
            checks["internalUSBFunctionsExcluded"] = live.connections.allSatisfy { connection in
                !live.nodes.contains { connection.roots.contains($0.id) && $0.builtIn }
            }
            details["liveConnectionCount"] = live.connections.count
            details["liveResourceCount"] = live.endpoints.count
            details["liveCoverageWarnings"] = live.issues
            if let first = live.connections.first {
                let report = try await CableImpactScanner.scan(connection: first, inventory: live)
                checks["liveReadOnlyAnalysisCompleted"] = report.connectionID == first.id
            }
            let sockets = try OwnedCableSockets()
            let connection = CableConnection(name: "Owned loopback fixture", roots: [1])
            let network = CableEndpoint(id: "network", name: "Owned loopback", kind: .network, registryIDs: [2],
                                         interfaceName: "lo0", addresses: ["127.0.0.1"])
            let inventory = CableInventory(nodes: [.init(id: 1, name: "Fixture", kind: .usb), .init(id: 2, parents: [1], name: "Loopback", kind: .network)],
                                            connections: [connection], endpoints: [network])
            let report = try await CableImpactScanner.scan(connection: connection, inventory: inventory)
            checks["actualOwnedTCPSessionAttributed"] = report.sessions["network"]?.contains { $0.pid == getpid() && $0.remote.hasSuffix(":\(sockets.port)") } == true
            sockets.close()
            checks["ownedSocketsClosed"] = sockets.closed

            let fixture = makeFixture()
            let model = CableImpactModel(read: { fixture }, scan: { connection, inventory, extra, manual in
                try await CableImpactScanner.scan(connection: connection, inventory: inventory, additionalConnections: extra,
                                                  manualEndpoints: manual, execute: fixtureExecute)
            }, stillPresent: { _ in true })
            await model.refresh()
            checks["fixtureAnalysisCompleted"] = await wait { model.report != nil }
            checks["allFourResourceKindsMapped"] = Set(model.affected.map { $0.endpoint.kind }) == Set([.storage, .network, .audio, .display])
            checks["unrelatedDisplayNotGuessed"] = !model.affected.contains { $0.id == "unassigned" }
            checks["ownedFixtureOpenFileWiredIntoUI"] = model.report?.diskUsers["disk"]?.first?.files.count == 1
            checks["SSHFixtureIdentified"] = model.report?.sessions["network"]?.first?.isSSH == true
            model.pairEndpoint("unassigned", enabled: true)
            checks["manualAssociationExplicit"] = await wait { model.report?.affected.contains { $0.id == "unassigned" && $0.evidence == .manual } == true }
            model.pairEndpoint("unassigned", enabled: false)
            checks["manualAssociationReversible"] = await wait { model.report != nil && !model.affected.contains { $0.id == "unassigned" } }
            let ownedWindow = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 700, height: 680),
                                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            ownedWindow.isReleasedWhenClosed = false
            window = ownedWindow
            ownedWindow.title = "MacPocket — Cable impact audit"
            ownedWindow.appearance = NSAppearance(named: CommandLine.arguments.contains("--audit-dark") ? .darkAqua : .aqua)
            ownedWindow.contentViewController = NSHostingController(rootView: CableImpactView(model: model, observesHardware: false)
                .buttonStyle(.pocketSecondary).background(Color(nsColor: .windowBackgroundColor)))
            ownedWindow.makeKeyAndOrderFront(nil)
            var layouts: [[String: Any]] = []
            for width in [700, 1060] {
                ownedWindow.setContentSize(NSSize(width: width, height: width == 700 ? 680 : 820))
                try await Task.sleep(for: .milliseconds(500))
                ownedWindow.contentView?.layoutSubtreeIfNeeded()
                let nodes = ToolUIAudit.accessibilityNodes(ownedWindow)
                layouts.append(["width": width, "accessibilityElements": nodes.count])
                checks["nativeUIHasControls\(width)"] = nodes.contains { $0["role"] == "AXPopUpButton" || $0["role"] == "AXButton" }
                try await capture(ownedWindow, destination: directory.appendingPathComponent("ui-\(width).png"))
                checks["ownWindowCaptured\(width)"] = true
            }
            details["layouts"] = layouts
            details["language"] = Bundle.main.preferredLocalizations.first ?? "unknown"
            model.stop()
            ownedWindow.close()
            window = nil
        } catch { failure = error.localizedDescription
        window?.close() }
        let report: [String: Any] = ["passed": failure == nil && !checks.isEmpty && checks.values.allSatisfy { $0 },
            "checks": checks, "details": details, "error": failure ?? "", "physicalDisconnectTested": false,
            "scope": "live-read-only-inventory; owned-loopback-TCP; synthetic-dock-UI", "systemSettingsChanged": false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        }
    }
    private static func capture(_ window: NSWindow, destination: URL) async throws {
        guard WindowPreviewProvider.permitted else { throw WindowPreviewError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { throw WindowPreviewError.unavailable }
        let filter = SCContentFilter(desktopIndependentWindow: target), config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw WindowPreviewError.unavailable }
        try png.write(to: destination)
    }
    private static func makeFixture() -> CableInventory {
        let nodes: [CableRegistryNode] = [.init(id: 1, name: "Studio Dock · fixture", kind: .usb),
            .init(id: 2, parents: [1], name: "Ethernet", kind: .network), .init(id: 3, parents: [1], name: "Project SSD", kind: .media),
            .init(id: 4, parents: [1], name: "Monitor", kind: .display), .init(id: 5, parents: [1], name: "Audio", kind: .audio)]
        let connection = CableConnection(name: "Studio Dock · fixture", roots: [1])
        let endpoints: [CableEndpoint] = [
            .init(id: "disk", name: "Project SSD", kind: .storage, registryIDs: [3], detail: "/Volumes/Audit Project", active: true),
            .init(id: "network", name: "USB Ethernet", kind: .network, registryIDs: [2], detail: "en99", active: true, isDefault: true, interfaceName: "en99", addresses: ["192.0.2.2"]),
            .init(id: "display", name: "Studio Monitor", kind: .display, registryIDs: [4], detail: "3840 × 2160", active: true, isDefault: true),
            .init(id: "audio", name: "USB Audio", kind: .audio, registryIDs: [5], active: true, isDefault: true),
            .init(id: "unassigned", name: "Other Monitor · fixture", kind: .display)]
        let drive = EjectDrive(id: "disk99", identity: "fixture", name: "Project SSD", connection: "USB", capacity: 1000,
                               volumes: [.init(id: "disk99s1", name: "Audit Project", mountPath: "/Volumes/Audit Project")])
        return .init(nodes: nodes, connections: [connection], endpoints: endpoints, drives: ["disk": drive])
    }
    nonisolated private static let fixtureExecute: USBEject.Execute = { _, args, _ in
        if args.contains("-iTCP") { return .init(status: 0, output: "p4242\0cssh\0n192.0.2.2:50000->192.0.2.9:22\0", errorOutput: "") }
        return .init(status: 0, output: "p4243\0cVideo Editor\0f4\0n/Volumes/Audit Project/Render.mov\0", errorOutput: "")
    }
}

/// Only talks to 127.0.0.1. Every descriptor is owned and closed even if the audit throws.
private final class OwnedCableSockets {
    private var descriptors: [Int32] = []
    let port: UInt16
    var closed: Bool { descriptors.isEmpty }
    init() throws {
        var owned: [Int32] = [], completed = false
        defer { if !completed { for fd in owned { Darwin.close(fd) } } }
        let server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard server >= 0 else { throw POSIXError(.EIO) }
        owned.append(server)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, Darwin.listen(server, 1) == 0 else { throw POSIXError(.EIO) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(server, $0, &size) } }
        guard named == 0 else { throw POSIXError(.EIO) }
        port = UInt16(bigEndian: address.sin_port)
        let client = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard client >= 0 else { throw POSIXError(.EIO) }
        owned.append(client)
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, size) } }
        guard connected == 0 else { throw POSIXError(.EIO) }
        let accepted = Darwin.accept(server, nil, nil)
        guard accepted >= 0 else { throw POSIXError(.EIO) }
        owned.append(accepted)
        descriptors = owned
        completed = true
    }
    func close() { for fd in descriptors { Darwin.close(fd) }; descriptors = [] }
    deinit { close() }
}
#endif
