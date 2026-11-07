#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

actor SwitcherManualFocusCatalog: WindowCatalogServing {
    private let base: any WindowCatalogServing
    private(set) var completedFocusIDs: [String] = []
    init(_ base: any WindowCatalogServing) { self.base = base }
    func snapshot() async -> WindowCatalogReport { await base.snapshot() }
    func focus(_ id: String) async throws { try await base.focus(id);completedFocusIDs.append(id) }
    func focusDestination(_ id: String) async -> WindowFocusDestination? { await base.focusDestination(id) }
    func perform(_ action: WindowAction,on id: String) async throws { throw WindowCatalogError.unsupported }
    func noteApplicationActivation(_ pid: Int32) async { await base.noteApplicationActivation(pid) }
}

/// Waits for real registered Carbon callbacks and independently verifies the selected AX window.
/// It never posts keyboard events and can only focus the separately owned fixture through its catalog.
@MainActor enum SwitcherManualKeyboardAudit {
    private final class Trace: NSObject,NSWindowDelegate {
        var cancelled = false
        var events: [(id: UInt32,session: UUID?)] = []
        var releaseSessions = Set<UUID>()
        var sawPanel = false,sawThumbnails = false
        func windowWillClose(_ notification: Notification) { cancelled = true }
    }
    private final class Guide: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private struct Instructions: View {
        let phase: Int,chord: String,cancel: () -> Void
        var body: some View {
            VStack(alignment: .leading,spacing: 14) {
                Text("Fiziksel kısayol testi").font(.headline)
                Text(verbatim: "\(phase)/2 · \(chord)").font(.title2.monospaced())
                Text("Değiştiriciyi basılı tutarak Tab'a bas. Kartlar görününce Shift+Tab'a bas, sonra değiştiriciyi bırak.")
                    .fixedSize(horizontal: false,vertical: true)
                Text("Yalnız iki test penceresi arasında geçiş yapılır.").font(.caption).foregroundStyle(.secondary)
                Button("Vazgeç",action: cancel)
            }.padding(24).frame(width: 520,height: 280,alignment: .leading)
        }
    }
    static func run(controller: WindowSwitcherHotkeyController,catalog: SwitcherManualFocusCatalog,expectedID: String,fixturePID: Int32,expectedWindow: UInt32,
                    autoCancel: Bool = false,
                    guideSnapshot: URL? = nil,
                    activateFixture: () async throws -> Void,focusedWindow: () -> UInt32?) async throws -> [String:Any] {
        let trace = Trace()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0,y: 0,width: 1280,height: 800)
        let guide = Guide(contentRect: NSRect(x: screen.minX+20,y: screen.maxY-320,width: 520,height: 280),
            styleMask: [.titled,.closable,.nonactivatingPanel],backing: .buffered,defer: false)
        guide.isReleasedWhenClosed = false;guide.title = String(localized: "Fiziksel kısayol testi")
        guide.level = .floating;guide.delegate = trace
        defer {
            controller.onCarbonInvocationForAudit = nil;controller.onModifierReleaseCommitForAudit = nil
            controller.hideFromCommand();guide.delegate = nil;guide.close()
        }
        let cancellation = Task { @MainActor in
            if autoCancel {
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                trace.cancelled = true
            }
        }
        defer { cancellation.cancel() }
        var checks: [String:Bool] = [:],phases: [[String:Any]] = []
        var guideCaptured = false
        for (index,modifiers) in [SwitcherModifiers.option,.command].enumerated() {
            if trace.cancelled { break }
            controller.hideFromCommand()
            var shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: modifiers)
            shortcut.presentation.style = .thumbnails;shortcut.presentation.showThumbnails = true
            shortcut.presentation.previewSelected = false;shortcut.presentation.showBadges = false
            controller.saveShortcuts([shortcut])
            let prefix = "manualKeyboard-\(index+1)"
            checks[prefix+"BothCarbonKeysRegistered"] = controller.moduleDiagnosticResources["hotKeys"] == 2
            guard checks[prefix+"BothCarbonKeysRegistered"] == true else { throw WindowCatalogError.unsupported }
            trace.events = [];trace.releaseSessions = [];trace.sawPanel = false;trace.sawThumbnails = false
            let focusBaseline = await catalog.completedFocusIDs.count
            controller.onModifierReleaseCommitForAudit = { trace.releaseSessions.insert($0) }
            controller.onCarbonInvocationForAudit = { [weak controller] id,session in
                trace.events.append((id,session))
                trace.sawPanel = trace.sawPanel || controller?.commandPanelVisible == true
                trace.sawThumbnails = trace.sawThumbnails || controller?.model.thumbnails.count == 2
            }
            let host = NSHostingView(rootView: Instructions(phase: index+1,chord: shortcut.displayName,cancel: { trace.cancelled = true }))
            host.sizingOptions = [];host.frame = NSRect(x: 0,y: 0,width: 520,height: 280)
            host.autoresizingMask = [.width,.height]
            guide.contentView = host;guide.setContentSize(NSSize(width: 520,height: 280))
            guide.orderFrontRegardless()
            try await activateFixture()
            await controller.model.refresh()
            if index == 0,let guideSnapshot {
                guide.contentView?.layoutSubtreeIfNeeded();guide.displayIfNeeded()
                let app = NSRunningApplication.current
                let inventory = await WindowCatalog().snapshot(processIDs: [app.processIdentifier],includingCurrentApplication: true)
                if let target = inventory.windows.first(where: { $0.windowID == UInt32(guide.windowNumber) }),
                   let image = try? await WindowPreviewProvider().image(for: target,maxPixels: CGSize(width: 1040,height: 560)),
                   let png = NSBitmapImageRep(cgImage: image.cgImage).representation(using: .png,properties: [:]) {
                    try png.write(to: guideSnapshot,options: .atomic);guideCaptured = true
                }
            }
            let deadline = ProcessInfo.processInfo.systemUptime+60
            var completed = false,sameSession = false
            while !trace.cancelled,ProcessInfo.processInfo.systemUptime < deadline {
                trace.sawPanel = trace.sawPanel || controller.commandPanelVisible
                trace.sawThumbnails = trace.sawThumbnails || controller.model.thumbnails.count == 2
                if let last = trace.events.last,let token = last.session {
                    let ids = Set(trace.events.filter { $0.session == token }.map(\.id))
                    sameSession = ids.contains(1) && ids.contains(2)
                    let focus = await catalog.completedFocusIDs
                    completed = sameSession && trace.releaseSessions.contains(token) && focus.count > focusBaseline && focus.last == expectedID
                        && !controller.commandPanelVisible && !controller.preparingForAudit
                        && controller.model.selection == expectedID && controller.model.failure == nil
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID && focusedWindow() == expectedWindow
                        && controller.moduleDiagnosticResources["focusTask"] == 0
                }
                if completed { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            checks[prefix+"ForwardAndReverseInSameHeldSession"] = sameSession
            checks[prefix+"ActualSelectedWindowAfterRelease"] = completed
            checks[prefix+"AnimatedCardPanelObserved"] = trace.sawPanel
            checks[prefix+"BothRealThumbnailsObserved"] = trace.sawThumbnails
            phases.append(["chord":shortcut.displayName,"callbacks":trace.events.map { ["id":Int($0.id),"session":$0.session?.uuidString ?? "none"] },
                "completed":completed,"releaseSessions":trace.releaseSessions.map(\.uuidString),
                "newSuccessfulFocusCalls":await catalog.completedFocusIDs.count-focusBaseline,
                "sawPanel":trace.sawPanel,"sawThumbnails":trace.sawThumbnails])
            if !completed { break }
            // Do not let the release that finished one phase trigger the next profile.
            controller.hideFromCommand()
            try await Task.sleep(for: .milliseconds(200))
        }
        checks["manualKeyboardBothPhasesCompleted"] = phases.count == 2 && phases.allSatisfy { $0["completed"] as? Bool == true }
        checks["manualKeyboardNotCancelled"] = !trace.cancelled
        let passed = !checks.isEmpty && checks.values.allSatisfy { $0 }
        return ["checks":checks,"phases":phases,"physicalKeyboardVerified":passed,"generatedInputUsed":false,
                "cancelled":trace.cancelled,"guideScreenshotCaptured":guideCaptured,"perPhaseDeadlineSeconds":60]
    }
}
#endif
