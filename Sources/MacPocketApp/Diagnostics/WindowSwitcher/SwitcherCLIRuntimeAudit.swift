#if DEBUG
import AppKit
import MacPocketCore

private actor CLIWindowFixture: WindowCatalogServing {
    let rows: [SwitchableWindow]
    private(set) var focused: [String] = []
    init() {
        rows = (1...2).map { index in
            SwitchableWindow(id: "cli-fixture-\(index)",processID: getpid(),application: "MacPocket CLI Fixture",title: "CLI \(index)",applicationURL: nil,
                minimized: false,hidden: false,fullScreen: false,frontmost: false,windowAccessible: true,canClose: false,canMinimize: false,canFullScreen: false,
                launchedAt: nil,lastFocusedAt: Date(timeIntervalSince1970: Double(index)),windowID: UInt32(index))
        }
    }
    func snapshot() async -> WindowCatalogReport { .init(windows: rows,accessibilityGranted: true,partial: false) }
    func focus(_ id: String) async throws { focused.append(id) }
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

@MainActor enum SwitcherCLIRuntimeAudit {
    static func run(checks: inout [String:Bool]) async throws {
        let suite = "MacPocket.CLIAudit."+UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removePersistentDomain(forName: suite) }
        SwitcherShortcutStore.save([.defaultOptionTab],defaults)
        let catalog = CLIWindowFixture()
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults,permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: model,gestureSettings: defaults)
        // Starts the owned fixture relay and ordinary local panel without registering global hotkeys.
        controller.beginGestureAudit()
        defer { controller.stopForModule() }
        let service = SwitcherCommandService(controller: controller)
        let name = "com.doancan.MacPocket.CLIAudit."+UUID().uuidString
        let listener = try SwitcherCLIListener(portName: name) { await service.execute($0) }
        defer { listener.stop() }
        func send(_ command: SwitcherCLICommand) async throws -> SwitcherCLIResponse {
            try await Task.detached { try SwitcherCLITransport.send(.init(command: command),portName: name) }.value
        }
        let list = try await send(.list(detailed: false))
        checks["cliMachListUsesSharedCatalogMRU"] = list.windows?.map(\.id) == ["cli-fixture-2","cli-fixture-1"] && list.windows?.map(\.mru) == [1,2]
        checks["cliCompactListOmitsDetails"] = list.windows?.allSatisfy { $0.details == nil } == true
        let detailed = try await send(.list(detailed: true))
        checks["cliDetailedListCarriesPIDAndPermissionScope"] = detailed.windows?.allSatisfy { $0.details?.processID == getpid() } == true && detailed.accessibility == true && detailed.partial == false
        let initial = try await send(.status)
        checks["cliInitialPanelIsClosed"] = initial.panelVisible == false
        let shown = try await send(.show(1))
        let end = ContinuousClock.now + .seconds(2)
        while model.busy,ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(20)) }
        checks["cliShowOpensRealNativePanel"] = shown.status == "opening" && controller.commandPanelVisible && controller.auditPanel?.isVisible == true
        let selection = model.selection
        let repeated = try await send(.show(1))
        checks["cliRepeatedShowDoesNotCycleSelection"] = repeated.errorCode == nil && selection != nil && model.selection == selection
        var edited = SwitcherShortcut.defaultOptionTab
        edited.filter.includeHidden = false
        SwitcherShortcutStore.save([edited],defaults)
        controller.beginGestureAudit()
        let updated = try await send(.show(1))
        checks["cliShowRefreshesEditedProfile"] = updated.errorCode == nil && controller.activeShortcut == edited && controller.commandPanelVisible
        let status = try await send(.status)
        checks["cliStatusReadsVisibleNativePanel"] = status.panelVisible == true
        let invalidProfile = try await send(.show(9))
        checks["cliUnavailableProfileKeepsCurrentPanel"] = invalidProfile.errorCode == "unavailable" && controller.commandPanelVisible && model.selection == selection
        let hidden = try await send(.hide)
        let beforeFocus = await catalog.focused
        checks["cliHideDismissesWithoutCommitting"] = hidden.status == "hidden" && hidden.panelVisible == false && !controller.commandPanelVisible && beforeFocus.isEmpty
        let numeric = try await send(.focus("1")),mru = try await send(.focusMRU(1))
        let focused = await catalog.focused
        checks["cliFocusCommandsReachOwnedCatalog"] = numeric.status == "focused" && mru.status == "focused" && focused == ["cli-fixture-1","cli-fixture-2"]
        let missing = try await send(.focus("nonexistent-cli-owned-target"))
        let afterMissing = await catalog.focused
        checks["cliMissingTargetReportsErrorWithoutAnotherFocus"] = missing.errorCode == "not-found" && afterMissing == focused
        controller.stopForModule()
        let disabled = try await send(.show(1))
        checks["cliDisabledModuleDoesNotOpenPanel"] = disabled.errorCode == "unavailable" && !controller.commandPanelVisible
        listener.stop()
        do { _ = try await send(.status);checks["cliStoppedServerFailsExplicitly"] = false }
        catch SwitcherCLIError.notRunning { checks["cliStoppedServerFailsExplicitly"] = true }
        catch { checks["cliStoppedServerFailsExplicitly"] = false }
        // A real child of this isolated bundle exercises the shipped executable's early client entry.
        // Only status and a parser-invalid show are sent to its ordinary app-delegate endpoint.
        if let executable = Bundle.main.executableURL {
            let status = try await client(executable,arguments: ["--switcher","status"])
            let decoded = try? JSONDecoder().decode(SwitcherCLIResponse.self,from: status.1)
            checks["cliBundledExecutableCrossProcessStatus"] = status.0 == 0 && decoded?.status == "ok" && decoded?.panelVisible != nil
            let invalid = try await client(executable,arguments: ["--switcher","show","0"])
            checks["cliBundledExecutableRejectsInvalidArguments"] = invalid.0 == 1 && invalid.1.isEmpty && !invalid.2.isEmpty
        } else { checks["cliBundledExecutableExists"] = false }
    }

    private static func client(_ executable: URL,arguments: [String]) async throws -> (Int32,Data,Data) {
        // Foundation waitUntilExit on a cooperative worker can miss process-exit delivery.
        // Reuse the app's continuation-based runner with output draining and a hard time limit.
        let result = try await BoundedProcess.run(executable.path,arguments,timeout: 5)
        return (result.status,Data(result.output.utf8),Data(result.errorOutput.utf8))
    }
}
#endif
