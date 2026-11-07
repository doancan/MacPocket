import AppKit
import Darwin

/// macOS 27 renders status items in MenuBarAgent. Resolve its compatibility interface at runtime;
/// do not link private frameworks or assume that the older per-window layout still works.
@MainActor final class MenuBarVisibilityController {
    private static let initialize = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activate = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidate = NSSelectorFromString("invalidate")
    private let assertionType: NSObject.Type?
    private let configurationType: NSObject.Type?
    private var active: NSObject?
    private var pending: NSObject?
    private var timeout: Timer?
    private var completion: ((String?) -> Void)?
    private var generation = UUID()
    var isAvailable: Bool { assertionType != nil && configurationType != nil }
    init() {
        guard dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != nil,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              assertion.instancesRespond(to: Self.activate), assertion.instancesRespond(to: Self.invalidate),
              configuration.instancesRespond(to: Self.initialize) else {
            assertionType = nil; configurationType = nil; return
        }
        assertionType = assertion; configurationType = configuration
    }
    func apply(allowing bundleIDs: Set<String>, completion: @escaping (String?) -> Void) {
        cancelPending()
        guard let assertionType, let configurationType,
              let allocated = (configurationType as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let configuration = allocated.perform(Self.initialize, with: (0..<9).map(NSNumber.init(value:)) as NSArray,
                  with: bundleIDs.sorted() as NSArray)?.takeRetainedValue() else {
            completion(String(localized: "Bu macOS sürümünde menü çubuğu görünürlüğü yönetilemiyor."));return
        }
        let token = UUID(); generation = token
        let object = assertionType.init(); pending = object; self.completion = completion
        let callback: @convention(block) (NSError?) -> Void = { [weak self] error in
            let message = error?.localizedDescription
            Task { @MainActor in self?.finish(token: token, error: message) }
        }
        object.perform(Self.activate, with: configuration, with: callback as AnyObject)
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(token: token, error: String(localized: "Menü çubuğu yanıt vermedi; görünürlük değiştirilmedi.")) }
        }
        timeout = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func finish(token: UUID, error: String?) {
        guard generation == token, let object = pending else { return }
        timeout?.invalidate(); timeout = nil; pending = nil
        let callback = completion; completion = nil
        if error == nil { active?.perform(Self.invalidate); active = object }
        else { object.perform(Self.invalidate) }
        callback?(error)
    }
    private func cancelPending() {
        generation = UUID(); timeout?.invalidate(); timeout = nil
        pending?.perform(Self.invalidate); pending = nil
        completion = nil
    }
    func release() {
        cancelPending(); active?.perform(Self.invalidate); active = nil
    }
    isolated deinit { release() }
}
