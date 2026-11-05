#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

private struct PermissionUsageFixture: View {
    let modules: Set<PocketModule>
    let request: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(OnboardingPermission.allCases) { permission in
                    OnboardingPermissionRow(permission: permission, state: .notGranted,
                        usage: PermissionUsageMap.usage(permission, availableModules: modules),
                        audioOnlyNote: permission == .screenRecording && modules.contains(.mixer), requested: false, request: request)
                }
            }.padding(20)
        }.background(PocketTheme.background)
    }
}

@MainActor enum PermissionUsageRuntimeAudit {
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested else { return [:] }
        var checks: [String: Bool] = [:], requests = 0
        let model = OnboardingModel()
        model.request(.accessibility)
        checks["permissionsInactiveModuleDoesNotRequestOSAccess"] = model.requested.isEmpty && PermissionDragHelper.shared.permission == nil
        checks["permissionsAllOffRequiresOnlyCorePermissions"] = model.applicable == [.fullDiskAccess, .location, .notifications]
        UserDefaults.standard.set(true, forKey: PocketModule.screenshot.availabilityKey)
        await model.refresh()
        checks["permissionsModelRefreshTracksAvailability"] = model.usage(.screenRecording).activeModules == [.screenshot]
        UserDefaults.standard.set(false, forKey: PocketModule.screenshot.availabilityKey)
        await model.refresh()
        checks["permissionsModelRefreshRemovesDisabledDependency"] = !model.usage(.screenRecording).isRelevant
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 840), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); window.contentView = nil }
        func render(_ modules: Set<PocketModule>, suffix: String) async -> [[String: String]] {
            let hosting = NSHostingView(rootView: PermissionUsageFixture(modules: modules, request: { requests += 1 }))
            hosting.sizingOptions = []; window.contentView = hosting; window.setContentSize(CGSize(width: 960, height: 840))
            window.center(); window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(150))
            if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: destination.appendingPathExtension(suffix + ".png")) }
            }
            let nodes = ToolUIAudit.accessibilityNodes(window)
            if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: destination.appendingPathExtension(suffix + ".ax.json")) }
            return nodes
        }
        let off = await render([], suffix: "permissions-off")
        let actionNames = [String(localized: "İzin Ver"), String(localized: "Ayarlarda Aç")]
        func actions(_ nodes: [[String: String]]) -> Int { nodes.filter { $0["role"] == "AXButton" && actionNames.contains($0["name"] ?? "") }.count }
        checks["permissionsAllOffShowsOnlyThreeCoreActions"] = actions(off) == 3
        let screenshot = await render([.screenshot], suffix: "permissions-screenshot")
        checks["permissionsScreenshotAddsOnlyScreenAction"] = actions(screenshot) == 4
        let all = await render(Set(PocketModule.allCases), suffix: "permissions-all")
        checks["permissionsAllModulesShowSixActions"] = actions(all) == 6
        let mixer = PermissionUsageMap.usage(.screenRecording, availableModules: [.mixer])
        checks["permissionsAudioOnlyDoesNotClaimScreenGrant"] = !mixer.isRelevant
        checks["permissionsRenderingNeverRequestsAccess"] = requests == 0
        return checks
    }
}
#endif
