import DiskArbitration
import Foundation

/// Observes media, partitions and mount/name changes. No approval callback or disk mutation is registered.
@MainActor final class DiskChangeObservation {
    private var session: DASession?
    private var pending: Timer?
    private var receive: (@MainActor () -> Void)?
    private static let appeared: DADiskAppearedCallback = { _, context in changed(context) }
    private static let disappeared: DADiskDisappearedCallback = { _, context in changed(context) }
    private static let descriptionChanged: DADiskDescriptionChangedCallback = { _, _, context in changed(context) }

    private nonisolated static func changed(_ context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        let observer = Unmanaged<DiskChangeObservation>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { observer.schedule() }
    }

    static func observe(_ receive: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)? {
        let observer = DiskChangeObservation()
        guard observer.start(receive) else { return nil }
        return { observer.stop() }
    }

    @discardableResult func start(_ receive: @escaping @MainActor () -> Void) -> Bool {
        stop()
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return false }
        self.session = session
        self.receive = receive
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, Self.appeared, context)
        DARegisterDiskDisappearedCallback(session, nil, Self.disappeared, context)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, Self.descriptionChanged, context)
        DASessionSetDispatchQueue(session, .main)
        // Initial disk enumeration joins the same burst as appearance callbacks.
        schedule()
        return true
    }

    private func schedule() {
        guard session != nil else { return }
        pending?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = nil
                self.receive?()
            }
        }
        pending = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        pending?.invalidate(); pending = nil
        receive = nil
        guard let session else { return }
        DASessionSetDispatchQueue(session, nil)
        let context = Unmanaged.passUnretained(self).toOpaque()
        DAUnregisterCallback(session, unsafeBitCast(Self.appeared, to: UnsafeMutableRawPointer.self), context)
        DAUnregisterCallback(session, unsafeBitCast(Self.disappeared, to: UnsafeMutableRawPointer.self), context)
        DAUnregisterCallback(session, unsafeBitCast(Self.descriptionChanged, to: UnsafeMutableRawPointer.self), context)
        self.session = nil
    }

    isolated deinit { stop() }
}
