#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

private actor UpdateCatalogFixture {
    private(set) var requests: [URL] = []
    var slow = false
    var failFeed = false
    func configure(slow: Bool = false, failFeed: Bool = false) { self.slow = slow; self.failFeed = failFeed }
    func fetch(_ url: URL) async throws -> Data {
        requests.append(url)
        if slow { try await Task.sleep(for: .seconds(2)) }
        if url.host == "itunes.apple.com" {
            return Data(#"{"resultCount":1,"results":[{"kind":"mac-software","bundleId":"audit.store","version":"2.0","trackId":12345,"minimumOsVersion":"12.0"}]}"#.utf8)
        }
        if failFeed { throw URLError(.cannotConnectToHost) }
        return Data("""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>11</sparkle:version><sparkle:shortVersionString>1.1</sparkle:shortVersionString><enclosure url="https://example.com/app.zip"/></item>
        <item><sparkle:version>12</sparkle:version><sparkle:shortVersionString>1.2b1</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel><enclosure url="https://example.com/beta.zip"/></item>
        <item><sparkle:version>200</sparkle:version><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion><enclosure url="https://example.com/future.zip"/></item>
        </channel></rss>
        """.utf8)
    }
}

@MainActor enum ApplicationUpdateRuntimeAudit {
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested, let root = ModuleRuntimeAudit.dataURL("update-fixture-" + UUID().uuidString) else { return [:] }
        let originalSettings = ApplicationUpdateSettings.load(from: .standard)
        let fixture = UpdateCatalogFixture(), scanner = ApplicationUpdateScanner(fetch: { try await fixture.fetch($0) }, requestPause: .zero)
        let model = ApplicationWorkspaceModel(updateScanner: scanner)
        defer { originalSettings.save(to: .standard); try? FileManager.default.removeItem(at: root) }
        var checks: [String: Bool] = [:]
        do {
            try app(root, name: "Store", id: "audit.store", store: true)
            try app(root, name: "Unmatched", id: "audit.unmatched", store: true)
            try app(root, name: "Publisher", id: "audit.publisher", feed: "https://update-fixture.example/feed.xml")
            try app(root, name: "SameBuild", id: "audit.samebuild", feed: "https://update-fixture.example/feed.xml", build: "11")
            try app(root, name: "NoFeed", id: "audit.nofeed", framework: true)
            model.applications = try await ApplicationInventory().scan(roots: [root]); model.loaded = true
            model.showUpdates = true
            model.updateSettings.sources = [.appStore, .sparkle]; model.updateSettings.country = "TR"
            await model.checkUpdates()
            checks["updatesStoreIdentityMatch"] = model.remoteUpdates.contains { $0.app.bundleID == "audit.store" && $0.release.version == "2.0" && $0.release.storeID == 12345 }
            checks["updatesUnmatchedIsNotReportedCurrent"] = model.updateSourceResults[.appStore]?.unmatched == 1
            checks["updatesMissingFeedSkipped"] = model.updateSourceResults[.sparkle]?.skipped == 1
            checks["updatesStableUsesBuildNotDisplayVersion"] = model.remoteUpdates.first { $0.source == .sparkle }?.release.version == "11"
            checks["updatesSameBuildIsNeverOfferedAgain"] = !model.remoteUpdates.contains { $0.app.bundleID == "audit.samebuild" }
            checks["updatesSharedFeedFetchedOncePerCheck"] = await fixture.requests.filter { $0.host == "update-fixture.example" }.count == 1
            checks["updatesChecksFinishWithoutBusyState"] = !model.checkingUpdates && model.currentUpdateSource == nil
            checks["updatesNoMetadataDownloadLinksFetched"] = await fixture.requests.allSatisfy { ["itunes.apple.com", "update-fixture.example"].contains($0.host) }

            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 820), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close(); window.contentView = nil }
            let hosting = NSHostingView(rootView: ApplicationsView(model: model).background(PocketTheme.background))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setContentSize(CGSize(width: 960, height: 820))
            window.center(); window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(250))
            checks["updatesNativeWindowUsesRequestedViewport"] = window.contentView?.bounds.size == CGSize(width: 960, height: 820)
            let nodes = snapshot(window, to: destination.appendingPathExtension("update-sources.png"))
            let toggles = nodes.filter { ["AXSwitch", "AXCheckBox"].contains($0["role"] ?? "") }
            checks["updatesSourceTogglesNamed"] = ApplicationUpdateSource.allCases.allSatisfy { source in toggles.contains { $0["name"] == source.localizedTitle } }
            checks["updatesProviderActionsNamed"] = nodes.contains { $0["name"] == String(localized: "App Store’da Aç") } && nodes.contains { $0["name"] == String(localized: "Uygulamayı Aç") }

            model.updateSettings.includePrereleases = true
            checks["updatesSettingsChangeInvalidatesOldResults"] = model.remoteUpdates.isEmpty && model.updatesCheckedAt == nil
            await model.checkUpdates()
            checks["updatesPreviewChannelOptIn"] = model.remoteUpdates.first { $0.source == .sparkle }?.release.version == "12"
            await fixture.configure(failFeed: true)
            await model.checkUpdates()
            checks["updatesProviderFailureIsIsolated"] = model.remoteUpdates.contains { $0.source == .appStore } && model.updateSourceResults[.sparkle]?.failures.isEmpty == false
            try? await Task.sleep(for: .milliseconds(100))
            _ = snapshot(window, to: destination.appendingPathExtension("update-source-error.png"))
            await fixture.configure(slow: true)
            let task = Task { await model.checkUpdates() }
            for _ in 0..<50 { if model.checkingUpdates { break }; try? await Task.sleep(for: .milliseconds(10)) }
            model.cancelUpdateCheck(); await task.value
            checks["updatesCancellationClearsWorkAndKeepsExplicitState"] = !model.checkingUpdates && model.updateCheckCancelled && model.currentUpdateSource == nil
            model.updateSettings.sources = []
            checks["updatesPreferenceChangeClearsOldCancellation"] = !model.updateCheckCancelled && model.updatesCheckedAt == nil
            let before = await fixture.requests.count
            await model.checkUpdates()
            checks["updatesAllSourcesOffDoesNotFetch"] = await fixture.requests.count == before
            window.setContentSize(CGSize(width: 760, height: 820))
            try? await Task.sleep(for: .milliseconds(100))
            _ = snapshot(window, to: destination.appendingPathExtension("update-sources-off.png"))
            checks["updatesCompactViewportHonored"] = window.contentView?.bounds.size == CGSize(width: 760, height: 820)
            if CommandLine.arguments.contains("--audit-update-network") {
                // Public fixtures only. No installed application identifiers are transmitted by this audit.
                let url = try ApplicationUpdateURL.lookup(bundleIDs: ["com.apple.dt.Xcode", "com.culturedcode.ThingsMac"], country: "US")
                let data = try await ApplicationUpdateHTTP.fetch(url)
                let catalog = try AppStoreUpdateCatalog.decode(data, requested: ["com.apple.dt.Xcode", "com.culturedcode.ThingsMac"])
                checks["updatesPublicAppleHTTPSLookup"] = catalog["com.apple.dt.xcode"] != nil && catalog["com.culturedcode.thingsmac"] != nil
                let feed = try await ApplicationUpdateHTTP.fetch(URL(string: "https://sparkle-project.org/files/sparkletestcast.xml")!)
                checks["updatesOfficialSparkleHTTPSFeed"] = try SparkleUpdateCatalog.decode(feed).isEmpty == false
            }
        } catch { checks["updatesFixtureCompleted"] = false }
        return checks
    }
    private static func app(_ root: URL, name: String, id: String, store: Bool = false, feed: String? = nil, framework: Bool = false, build: String = "10") throws {
        let url = root.appendingPathComponent(name + ".app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var info = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": "1.0", "CFBundleVersion": build]
        if let feed { info["SUFeedURL"] = feed }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Info.plist"))
        if store {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("_MASReceipt"), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url.appendingPathComponent("_MASReceipt/receipt"))
        }
        if framework { try FileManager.default.createDirectory(at: url.appendingPathComponent("Frameworks/Sparkle.framework"), withIntermediateDirectories: true) }
    }
    private static func snapshot(_ window: NSWindow, to url: URL) -> [[String: String]] {
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        }
        let nodes = ToolUIAudit.accessibilityNodes(window)
        if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url.appendingPathExtension("ax.json")) }
        return nodes
    }
}
#endif
