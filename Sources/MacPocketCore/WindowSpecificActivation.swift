import AppKit
@preconcurrency import ApplicationServices
import Darwin

/// Optional, window-specific process activation. Public cooperative app activation alone does
/// not select a destination Space. This SPI asks WindowServer to front ONE existing window;
/// it never moves a window or adds/removes a Space. A targeted out-of-content mouse-down then
/// establishes key focus; no mouse-up or hardware cursor movement is sent. All pointers stay process-lifetime bound.
enum WindowSpecificActivation {
    enum Outcome: Equatable { case unavailable, invalidTarget, processUnavailable, cancelled, frontFailed(Int32), keyFailed(Int32), accepted }
    private static let functions = Functions.load()
    static func request(windowID: UInt32, processID: Int32) -> Outcome {
        guard let functions else { return .unavailable }
        guard !Task.isCancelled else { return .cancelled }
        guard windowID > 0, processID > 0 else { return .invalidTarget }
        // Never front a reused numeric ID belonging to a different process.
        let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]] ?? []
        guard rows.contains(where: { $0[kCGWindowNumber as String] as? UInt32 == windowID
            && $0[kCGWindowOwnerPID as String] as? Int32 == processID }) else { return .invalidTarget }
        var psn = ProcessSerialNumber()
        guard functions.process(processID, &psn) == 0 else { return .processUnavailable }
        guard !Task.isCancelled else { return .cancelled }
        let front = functions.front(&psn, windowID, 0x200)
        guard front == 0 else { return .frontFailed(front) }
        guard !Task.isCancelled else { return .cancelled }
        var record = WindowKeyEventRecord.make(windowID: windowID)
        let key = record.withUnsafeMutableBufferPointer { functions.post(&psn,$0.baseAddress!) }
        guard key == 0 else { return .keyFailed(key) }
        return .accepted
    }
    private final class Functions: @unchecked Sendable {
        typealias Process = @convention(c) (Int32, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
        typealias Front = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
        typealias Post = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
        let process: Process, front: Front, post: Post
        private let libraries: [UnsafeMutableRawPointer]
        private init(_ libraries: [UnsafeMutableRawPointer], process: Process, front: Front, post: Post) {
            self.libraries = libraries; self.process = process; self.front = front;self.post = post
        }
        static func load() -> Functions? {
            guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
            guard let hi = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY | RTLD_LOCAL) else { dlclose(sky); return nil }
            guard let p = dlsym(hi, "GetProcessForPID"), let f = dlsym(sky, "_SLPSSetFrontProcessWithOptions"),let post = dlsym(sky,"SLPSPostEventRecordTo") else { dlclose(sky); dlclose(hi); return nil }
            return Functions([sky,hi], process: unsafeBitCast(p, to: Process.self), front: unsafeBitCast(f, to: Front.self),post: unsafeBitCast(post,to: Post.self))
        }
    }
}


/// WindowServer event-record ABI independently observed in installed AltTab 11.7.1 with REA:
/// 0x1001ebf14, evidence ev_eb9ad42553153edd90d96b842e717a7c2d77cb36b3518cd64007171681fca3f2.
/// Allocate 256 zeroed bytes for a 248-byte record. The point is far beyond content/resize edges.
/// This is one targeted down record, not a down/up click pair or a global CGEvent post.
enum WindowKeyEventRecord {
    static func make(windowID: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0,count: 0x100)
        bytes[0x04] = 0xf8;bytes[0x08] = 0x01;bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { bytes.replaceSubrange(0x3c..<0x40,with: $0) }
        let location = CGPoint(x: 300_000,y: 300_000)
        withUnsafeBytes(of: location) { bytes.replaceSubrange(0x20..<0x30,with: $0) }
        return bytes
    }
}
