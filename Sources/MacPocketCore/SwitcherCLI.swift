import CoreFoundation
import Darwin
import Foundation

/// A MacPocket protocol, independent of AltTab's CLI wire format. Profile/MRU indexes are one-based.
public enum SwitcherCLICommand: Codable, Equatable, Sendable {
    case list(detailed: Bool), focus(String), focusMRU(Int), show(Int), hide, status

    public static func parse(_ arguments: [String]) throws -> Self {
        if arguments == ["list"] { return .list(detailed: false) }
        if arguments == ["list", "--detailed"] { return .list(detailed: true) }
        if arguments.count == 2, arguments[0] == "focus" {
            let command = Self.focus(arguments[1])
            guard command.valid else { throw SwitcherCLIError.invalidCommand }
            return command
        }
        if arguments.count == 3, arguments[0] == "focus", arguments[1] == "--mru",let index = Int(arguments[2]),index > 0 { return .focusMRU(index) }
        if arguments == ["show"] { return .show(1) }
        if arguments.count == 2, arguments[0] == "show",let index = Int(arguments[1]),(1...9).contains(index) { return .show(index) }
        if arguments == ["hide"] { return .hide }
        if arguments == ["status"] { return .status }
        throw SwitcherCLIError.invalidCommand
    }

    var valid: Bool {
        switch self {
        case .focus(let id): !id.isEmpty && id.utf8.count <= 512 && !id.hasPrefix("--")
        case .focusMRU(let index): index > 0
        case .show(let index): (1...9).contains(index)
        default: true
        }
    }
}

public struct SwitcherCLIRequest: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let expiresAt: Date
    public let command: SwitcherCLICommand
    public init(command: SwitcherCLICommand, expiresAt: Date = Date().addingTimeInterval(25)) {
        version = 1; id = UUID(); self.expiresAt = expiresAt; self.command = command
    }
    public var isValid: Bool { version == 1 && command.valid }
    public var isCurrent: Bool { isValid && expiresAt > Date() && expiresAt.timeIntervalSinceNow <= 30 }
}

public struct SwitcherCLIWindow: Codable, Sendable {
    public let id: String
    public let windowID: UInt32?
    public let title: String
    public let mru: Int
    public let details: Details?
    public struct Details: Codable, Sendable {
        public let processID: Int32
        public let application: String
        public let bundleIdentifier: String?
        public let minimized, hidden, fullScreen, otherSpace, actionable: Bool
        public let displayID: UInt32?
        public let spaceIDs: [UInt64]?
        public let spaceOrdinals: [Int]?
        public let unknownSpaceIDs: [UInt64]?
        public let lastFocusedAt: Date?
        public let creationSequence: UInt64?
        public let nativeTabOrdinal: Int?
        public let nativeTabCount: Int?
        public let frame: [Double]?
    }
    public init(_ window: SwitchableWindow, mru: Int, detailed: Bool) {
        id = window.id; windowID = window.windowID; title = window.title; self.mru = mru
        let frame = window.frame.map { [Double($0.minX),Double($0.minY),Double($0.width),Double($0.height)] }
        details = detailed ? Details(processID: window.processID,application: window.application,bundleIdentifier: window.bundleIdentifier,
            minimized: window.minimized,hidden: window.hidden,fullScreen: window.fullScreen,otherSpace: window.isOnAnotherSpace,
            actionable: window.windowAccessible,displayID: window.displayID,spaceIDs: window.spaceMembership?.spaces.map(\.id),
            spaceOrdinals: window.spaceMembership?.spaces.map(\.ordinal),unknownSpaceIDs: window.spaceMembership.map { $0.unknownIDs.sorted() },
            lastFocusedAt: window.lastFocusedAt,creationSequence: window.creationObservation?.sequence,
            nativeTabOrdinal: window.nativeTab?.ordinal,nativeTabCount: window.nativeTab?.count,
            frame: frame.flatMap { $0.allSatisfy(\.isFinite) ? $0 : nil }) : nil
    }
}

public struct SwitcherCLIResponse: Codable, Sendable {
    public let version: Int
    public let requestID: UUID
    public var status: String
    public var message: String?
    public var errorCode: String?
    public var windows: [SwitcherCLIWindow]?
    public var accessibility, partial, otherSpacesVisible, spaceMetadataAvailable, spaceMetadataPartial, panelVisible: Bool?
    public var targetID: String?
    public init(requestID: UUID, status: String = "ok", message: String? = nil, errorCode: String? = nil) {
        version = 1; self.requestID = requestID; self.status = status; self.message = message; self.errorCode = errorCode
    }
}

public enum SwitcherCLIError: Error, LocalizedError {
    case invalidCommand, notRunning, unavailable, timedOut, invalidResponse, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidCommand: String(localized: "Geçersiz pencere geçişi komutu. list [--detailed], focus <id>, focus --mru <1…>, show [1…9], hide veya status kullan.")
        case .notRunning: String(localized: "MacPocket çalışmıyor veya komut bağlantısı hazır değil. Uygulamayı açıp yeniden dene.")
        case .unavailable: String(localized: "Pencere geçişi komut bağlantısı kurulamadı.")
        case .timedOut: String(localized: "Pencere geçişi komutu zaman aşımına uğradı. İşlem sonucu doğrulanamadı.")
        case .invalidResponse: String(localized: "Pencere geçişi komutuna geçerli bir yanıt alınamadı.")
        case .tooLarge: String(localized: "Pencere geçişi komutunun verisi boyut sınırını aşıyor.")
        }
    }
}

/// Local, same-login-session Mach IPC. No filesystem socket, network listener, shell or TCC prompt.
public enum SwitcherCLITransport {
    public static func portName(bundleIdentifier: String = "com.doancan.MacPocket") -> String {
        "\(bundleIdentifier).switcher-cli.\(getuid())"
    }
    static let maximumRequestBytes = 4096
    static let maximumResponseBytes = 4 * 1024 * 1024

    public static func send(_ request: SwitcherCLIRequest, portName: String = portName()) throws -> SwitcherCLIResponse {
        guard request.isCurrent else { throw SwitcherCLIError.invalidCommand }
        let data = try JSONEncoder().encode(request)
        guard data.count <= maximumRequestBytes else { throw SwitcherCLIError.tooLarge }
        guard let remote = CFMessagePortCreateRemote(nil,portName as CFString) else { throw SwitcherCLIError.notRunning }
        var received: Unmanaged<CFData>?
        let timeout = max(0.01,request.expiresAt.timeIntervalSinceNow)
        let result = CFMessagePortSendRequest(remote,1,data as CFData,timeout,timeout,CFRunLoopMode.defaultMode.rawValue,&received)
        let response = received?.takeRetainedValue() as Data?
        guard result == kCFMessagePortSuccess else {
            if result == kCFMessagePortSendTimeout || result == kCFMessagePortReceiveTimeout { throw SwitcherCLIError.timedOut }
            throw SwitcherCLIError.unavailable
        }
        guard let response,response.count <= maximumResponseBytes,
              let reply = try? JSONDecoder().decode(SwitcherCLIResponse.self,from: response),reply.version == 1,reply.requestID == request.id else { throw SwitcherCLIError.invalidResponse }
        return reply
    }
}

/// The callback waits on a private serial queue; the app's main actor remains free to run async AX work.
public final class SwitcherCLIListener {
    private var port: CFMessagePort?
    private final class Handler: @unchecked Sendable {
        let execute: @Sendable (SwitcherCLIRequest) async -> SwitcherCLIResponse
        init(_ execute: @escaping @Sendable (SwitcherCLIRequest) async -> SwitcherCLIResponse) { self.execute = execute }
    }
    private final class ReplyBox: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: SwitcherCLIResponse?
        func set(_ value: SwitcherCLIResponse) { lock.withLock { self.value = value }; ready.signal() }
        func get() -> SwitcherCLIResponse? { lock.withLock { value } }
    }

    public init(portName: String = SwitcherCLITransport.portName(), handler: @escaping @Sendable (SwitcherCLIRequest) async -> SwitcherCLIResponse) throws {
        let box = Handler(handler)
        var context = CFMessagePortContext(version: 0,info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { raw in raw.map { UnsafeRawPointer(Unmanaged<Handler>.fromOpaque($0).retain().toOpaque()) } },
            release: { raw in if let raw { Unmanaged<Handler>.fromOpaque(raw).release() } },copyDescription: nil)
        var shouldFree = DarwinBoolean(false)
        guard let local = CFMessagePortCreateLocal(nil,portName as CFString,Self.receive,&context,&shouldFree),!shouldFree.boolValue else { throw SwitcherCLIError.unavailable }
        port = local
        CFMessagePortSetDispatchQueue(local,DispatchQueue(label: portName,qos: .userInitiated))
    }
    public func stop() { if let port { CFMessagePortInvalidate(port) }; port = nil }
    deinit { if let port { CFMessagePortInvalidate(port) } }

    private static let receive: CFMessagePortCallBack = { _,messageID,data,context in
        let request = data.flatMap { CFDataGetLength($0) <= SwitcherCLITransport.maximumRequestBytes ? try? JSONDecoder().decode(SwitcherCLIRequest.self,from: $0 as Data) : nil }
        let id = request?.id ?? UUID()
        var reply = SwitcherCLIResponse(requestID: id,status: "error",message: SwitcherCLIError.invalidCommand.localizedDescription,errorCode: "invalid-command")
        if messageID == 1,let request,request.isCurrent,let context {
            let handler = Unmanaged<Handler>.fromOpaque(context).takeUnretainedValue()
            let box = ReplyBox()
            let task = Task { box.set(await handler.execute(request)) }
            let timeout = max(0,request.expiresAt.timeIntervalSinceNow)
            if box.ready.wait(timeout: .now()+timeout) == .success,let result = box.get() { reply = result }
            else {
                task.cancel()
                reply = SwitcherCLIResponse(requestID: id,status: "error",message: SwitcherCLIError.timedOut.localizedDescription,errorCode: "timed-out")
            }
        }
        var encoded = try? JSONEncoder().encode(reply)
        if encoded == nil || encoded!.count > SwitcherCLITransport.maximumResponseBytes {
            encoded = try? JSONEncoder().encode(SwitcherCLIResponse(requestID: id,status: "error",message: SwitcherCLIError.tooLarge.localizedDescription,errorCode: "response-too-large"))
        }
        return encoded.map { Unmanaged.passRetained($0 as CFData) }
    }
}
