#if DEBUG
import AppKit
import Darwin
import MacPocketCore
import ScreenCaptureKit

@MainActor enum ProductExpansionRuntimeAudit {
    static var nativeRequested: Bool { CommandLine.arguments.contains("--audit-product-expansion-native") }
    static func runNativeIfRequested() {
        guard nativeRequested else { return }
        var overrides = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        overrides[PocketPreferenceKey.showWindowAtLaunch] = false
        for module in PocketModule.allCases { overrides[module.availabilityKey] = false }
        UserDefaults.standard.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
    }
    static func launchNative() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--audit-product-expansion-native"), args.indices.contains(index + 2) else { NSApp.terminate(nil);return }
        NSApp.setActivationPolicy(.accessory)
        let destination = URL(fileURLWithPath: args[index + 1]), fixture = URL(fileURLWithPath: args[index + 2])
        Task { @MainActor in await native(destination: destination, fixture: fixture); NSApp.terminate(nil) }
    }
    private static func native(destination: URL, fixture: URL) async {
        var checks: [String:Bool] = [:], error: String?
        var diagnostics: [String:Any] = [:]
        let suite = "MacPocket.ExpansionAudit." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let service = MenuBarOrganizerService(defaults: defaults, autosavePrefix: suite)
        var owned: NSRunningApplication?
        func markerPixels() async throws -> Int {
            guard WindowPreviewProvider.permitted else { throw WindowPreviewError.permissionRequired }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let bars = content.windows.filter { $0.frame.height < 100 && $0.title?.lowercased().contains("menubar") == true }
            guard !bars.isEmpty else { throw WindowPreviewError.unavailable }
            var pairs = 0
            for bar in bars {
                let filter = SCContentFilter(desktopIndependentWindow: bar)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
                configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
                configuration.showsCursor = false; configuration.ignoreShadowsSingleWindow = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let width = image.width, height = image.height
                guard width > 0, height > 0, width < 20000, height < 400 else { continue }
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                bytes.withUnsafeMutableBytes { storage in
                    guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
                for y in 0..<height {
                    for x in 0..<width {
                        let index = (y * width + x) * 4
                        if bytes[index] > 180 && bytes[index+1] < 100 && bytes[index+2] > 180 {
                            for delta in 1...24 where x + delta < width {
                                let other = index + delta * 4
                                if bytes[other] < 100 && bytes[other+1] > 180 && bytes[other+2] < 100 { pairs += 1; break }
                            }
                        }
                    }
                }
            }
            return pairs
        }
        func count(_ app: NSRunningApplication) -> Int? {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXExtrasMenuBarAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(unsafeDowncast(value, to: AXUIElement.self), kAXChildrenAttribute as CFString, &children) == .success else { return nil }
            let bars = NSScreen.screens.compactMap { screen -> CGRect? in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
                let bounds = CGDisplayBounds(id)
                return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: NSStatusBar.system.thickness + 4)
            }
            return (children as? [AXUIElement])?.filter { element in
                var position: CFTypeRef?, size: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                      AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                      let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return false }
                var point = CGPoint.zero, extent = CGSize.zero
                AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point)
                AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
                return bars.contains { $0.contains(CGPoint(x: point.x + extent.width/2, y: point.y + extent.height/2)) }
            }.count
        }
        func describe(_ app: NSRunningApplication) -> [[String:String]] {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            var bar: CFTypeRef?; AXUIElementCopyAttributeValue(root, kAXExtrasMenuBarAttribute as CFString, &bar)
            guard let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [["bar":"none"]] }
            var children: CFTypeRef?; AXUIElementCopyAttributeValue(unsafeDowncast(bar, to: AXUIElement.self), kAXChildrenAttribute as CFString, &children)
            return (children as? [AXUIElement] ?? []).map { item in
                var values: [String:String] = [:]
                for key in ["AXTitle","AXDescription","AXPosition","AXSize","AXHidden","AXVisible","AXEnabled"] {
                    var value: CFTypeRef?; let status = AXUIElementCopyAttributeValue(item, key as CFString, &value)
                    if let value { values[key] = String(describing: value) } else { values[key] = "error \(status.rawValue)" }
                }
                return values
            }
        }
        func wait(_ predicate: () -> Bool) async -> Bool {
            for _ in 0..<120 { if predicate() { return true };try? await Task.sleep(for: .milliseconds(25)) }
            return false
        }
        do {
            guard AXIsProcessTrusted(), fixture.lastPathComponent == "MenuBarFixture.app" else { throw WindowCatalogError.permissionRequired }
            let baseline = try await markerPixels()
            diagnostics["baselineMarkerPixels"] = baseline
            let receipt = destination.deletingLastPathComponent().appendingPathComponent("pressed-receipt.json")
            try? FileManager.default.removeItem(at: receipt)
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false; configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--pressed-receipt",receipt.path]
            let app = try await NSWorkspace.shared.openApplication(at: fixture, configuration: configuration)
            owned = app
            guard app.bundleIdentifier == "com.doancan.MacPocket.MenuFixture" else { throw WindowCatalogError.unsupported }
            checks["ownedFixtureVisibleBeforeRestriction"] = await wait { (count(app) ?? 0) > 0 }
            let shown = try await markerPixels()
            diagnostics["visibleMarkerPixels"] = shown
            checks["ownedMarkerActuallyVisible"] = shown > baseline + 40
            diagnostics["before"] = describe(app)
            service.start(); service.setEnabled(true)
            checks["nativeVisibilityInterfaceAvailable"] = service.isAvailable
            service.setHidden(true, for: app.bundleIdentifier!)
            service.setCollapsed(true)
            checks["restrictionAcknowledged"] = await wait { !service.changingVisibility && service.collapsed }
            var hidden = try await markerPixels()
            for _ in 0..<20 where hidden > baseline + 16 {
                try await Task.sleep(for: .milliseconds(100))
                hidden = try await markerPixels()
            }
            diagnostics["hiddenMarkerPixels"] = hidden
            checks["ownedFixtureActuallyRemovedFromMenuBar"] = hidden <= baseline + 16
            diagnostics["hidden"] = describe(app)
            diagnostics["ownControls"] = describe(NSRunningApplication.current)
            try? await Task.sleep(for: .milliseconds(250))
            checks["ownedFixtureRemainsHidden"] = try await markerPixels() <= baseline + 16
            checks["controlRemainsOnScreen"] = await wait { (count(NSRunningApplication.current) ?? 0) > 0 }
            service.setCollapsed(false)
            checks["ownedFixtureRestored"] = await wait { (count(app) ?? 0) > 0 }
            try? await Task.sleep(for: .milliseconds(250))
            let restored = try await markerPixels()
            diagnostics["restoredMarkerPixels"] = restored
            checks["ownedMarkerActuallyRestored"] = restored > baseline + 40
            diagnostics["restored"] = describe(app)
            await service.refresh()
            if let item = service.items.first(where: { $0.processID == app.processIdentifier }) {
                service.open(item)
                checks["ownedItemAXPressDelivered"] = await wait { FileManager.default.fileExists(atPath: receipt.path) }
            } else { checks["ownedItemAXPressDelivered"] = false }
            let repository = GitHubRepository("sparkle-project/Sparkle")!
            let catalog = try await ApplicationUpdateHTTP.fetch(repository.apiURL)
            let releases = try GitHubReleaseCatalog.decode(catalog, repository: repository)
            checks["actualGitHubReleaseMetadataDecoded"] = !releases.isEmpty
        } catch let failure { error = failure.localizedDescription }
        service.stopForModule()
        checks["allOwnedControlsRemoved"] = service.diagnosticFrames.isEmpty
        if let owned { owned.terminate(); checks["ownedFixtureExits"] = await wait { owned.isTerminated } }
        defaults.removePersistentDomain(forName: suite)
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(suite) { UserDefaults.standard.removeObject(forKey: key) }
        let report: [String:Any] = ["passed":!checks.isEmpty && checks.values.allSatisfy { $0 } && error == nil,
            "checks":checks,"diagnostics":diagnostics,"error":error ?? "", "filterActivated":false,"applicationServicesStarted":false,"scope":"owned-separate-process-status-item-and-real-MenuBarAgent-assertion"]
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: destination, options: .atomic)
    }
}
#endif
