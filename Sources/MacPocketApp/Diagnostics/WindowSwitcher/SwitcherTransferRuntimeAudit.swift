#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor enum SwitcherTransferRuntimeAudit {
    fileprivate static weak var panelDriver: TransferFilePanelDriver?
    static func prepareFilePanelForAudit(_ panel: NSSavePanel) {
        guard WindowSwitcherRuntimeAudit.requested else { return }
        panelDriver?.prepareBeforePresentation(panel)
    }
    static func filePanelsVerified(_ checks: [String:Bool]) -> Bool {
        checks["transferRealFilePanelsComplete"] == true && checks.filter { $0.key.hasPrefix("transferReal") }.values.allSatisfy { $0 }
    }
    static func run(destination: URL,checks: inout [String: Bool]) async -> [[String:Any]] {
        let navigation = PocketSettingsNavigation.shared,previous = navigation.section
        defer { navigation.section = previous }
        var evidence: [[String:Any]] = []
        for width in [520.0,760.0] {
            var opens = 0
            var openedSections: [PocketSettingsNavigation.Section] = []
            let window = NSWindow(contentRect: NSRect(x: 120,y: 200,width: width,height: 240),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            func render(enabled: Bool) {
                window.contentView = NSHostingView(rootView: Form { SwitcherSettingsTransferLink(openOverride: { opens += 1;openedSections.append(navigation.section) }).disabled(!enabled) }
                    .formStyle(.grouped).environment(\.locale,pocketLocale))
                window.makeKeyAndOrderFront(nil)
            }
            render(enabled: true)
            await settle()
            navigation.section = .general
            let prefix = "transfer-settings-\(Int(width))",label = String(localized: "Ayar aktarımını aç…")
            let pressed = SwitcherAppearanceRuntimeAudit.press(label,in: window,role: .button)
            await settle()
            checks[prefix + "NativeButtonSelectsAdvancedBeforeOpeningSettings"] = pressed && opens == 1 && openedSections == [.advanced] && navigation.section == .advanced
            let nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix + "NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let width = Double(node["width"] ?? ""),width > 0 else { return false }
                return x < window.frame.minX - 2 || x+width > window.frame.maxX+2
            }
            checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + ".png"))
            render(enabled: false)
            await settle()
            navigation.section = .general
            _ = SwitcherAppearanceRuntimeAudit.press(label,in: window,role: .button)
            await settle()
            checks[prefix + "DisabledEntryDoesNotOpenSettings"] = opens == 1 && navigation.section == .general
            evidence.append(["width": width,"nodes": nodes,"settingsSceneOpened": false,"openAction": "owned-counter","navigation": "production-shared-route"])
            window.orderOut(nil)
        }
        let suite = "MacPocket.TransferAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { checks["transferDefaultsExist"] = false;return evidence }
        defer { defaults.removePersistentDomain(forName: suite) }
        do {
            let url = destination.appendingPathComponent("transfer-owned-settings.json")
            let rows = [SwitcherShortcut.defaultOptionTab,SwitcherShortcut(keyCode: SwitcherKeys.grave,modifiers: .option)]
            let profiles = try JSONEncoder().encode(rows)
            let data = try SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: profiles,"switcher.globalEnabled": false,"switcher.showBadges": false,"MacPocket.appearance": "dark"])
            try data.write(to: url,options: .atomic)
            defaults.set("keep",forKey: "Unrelated.key")
            try SettingsTransfer.importAndApply(SettingsTransfer.readImportData(from: url),to: defaults,domain: suite)
            checks["transferOwnedFileRoundTripsCompleteProfiles"] = defaults.data(forKey: SwitcherShortcutStore.key) == profiles && SwitcherShortcutStore.load(defaults) == rows
            checks["transferDisabledShortcutAndUnrelatedDataSurvive"] = !defaults.bool(forKey: "switcher.globalEnabled") && defaults.bool(forKey: "switcher.cardOverlayConfigured") && defaults.string(forKey: "Unrelated.key") == "keep"
            let previous = defaults.persistentDomain(forName: suite)!
            let corrupt = try JSONSerialization.data(withJSONObject: ["format": SettingsTransfer.format,"version": 1,"values": ["MacPocket.appearance": "light",SwitcherShortcutStore.key: ["$data": "%%%"]]])
            try corrupt.write(to: url,options: .atomic)
            var rejected = false
            do { try SettingsTransfer.importAndApply(SettingsTransfer.readImportData(from: url),to: defaults,domain: suite) } catch { rejected = true }
            checks["transferCorruptOwnedFileDoesNotChangeAnyPreferences"] = rejected && NSDictionary(dictionary: previous).isEqual(to: defaults.persistentDomain(forName: suite)!)
        } catch { checks["transferOwnedFileOperationsSucceed"] = false
        evidence.append(["error": error.localizedDescription]) }
        evidence.append(await realSettings(destination: destination,checks: &checks))
        return evidence
    }
    private static func realSettings(destination: URL,checks: inout [String:Bool]) async -> [String:Any] {
        guard WindowSwitcherRuntimeAudit.requested,Bundle.main.bundleIdentifier?.hasSuffix(".SwitcherAudit") == true else { return [:] }
        let window = NSWindow(contentRect: NSRect(x: 120,y: 180,width: 520,height: 200),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "MacPocket · Masaüstü testi")
        window.contentView = NSHostingView(rootView: Form { SwitcherSettingsTransferLink() }.formStyle(.grouped).environment(\.locale,pocketLocale))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        await settle()
        PocketSettingsNavigation.shared.section = .general
        let pressed = SwitcherAppearanceRuntimeAudit.press(String(localized: "Ayar aktarımını aç…"),in: window,role: .button)
        let deadline = ContinuousClock.now + .seconds(3)
        var settings: NSWindow?
        repeat {
            settings = NSApp.windows.first { candidate in
                candidate !== window && candidate.isVisible && ToolUIAudit.accessibilityNodes(candidate).contains { node in
                    node.values.contains(String(localized: "Dışa Aktar…"))
                }
            }
            if settings != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        checks["transferRealEntryOpensSettingsScene"] = pressed && settings != nil
        checks["transferRealEntrySelectsAdvancedSection"] = PocketSettingsNavigation.shared.section == .advanced && settings != nil
        var result: [String:Any] = ["settingsSceneOpened": settings != nil,"openOverrideUsed": false,
            "visibleWindows": NSApp.windows.filter(\.isVisible).map { ["class": NSStringFromClass(type(of: $0)),"identifier": $0.identifier?.rawValue ?? ""] }]
        if let settings {
            defer { settings.performClose(nil) }
            _ = WindowSwitcherRuntimeAudit.snapshot(settings,to: destination.appendingPathComponent("transfer-real-settings.png"))
            do {
                result["filePanels"] = try await filePanels(in: settings,destination: destination,checks: &checks)
                if !settings.isVisible {
                    _ = SwitcherAppearanceRuntimeAudit.press(String(localized: "Ayar aktarımını aç…"),in: window,role: .button)
                    let deadline = ContinuousClock.now + .seconds(3)
                    while !settings.isVisible,ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(30)) }
                    checks["transferRealSettingsReopensAfterClosingActiveSheet"] = settings.isVisible
                    if settings.isVisible {
                        let folder = destination.appendingPathComponent("real-transfer-"+UUID().uuidString,isDirectory: true)
                        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
                        let cancelled = await drivePanel(button: "Dışa Aktar…",in: settings,url: folder.appendingPathComponent("cancel-export.json"),kind: .save,cancel: true)
                        result["reopenedFilePicker"] = cancelled.evidence
                        checks["transferRealReopenedSettingsHasNoStalePanelLock"] = cancelled.observed && !cancelled.timedOut && cancelled.sheetParentID == settings.windowNumber
                    }
                }
            }
            catch { checks["transferRealFilePanelsComplete"] = false;result["error"] = error.localizedDescription }
        }
        return result
    }
    private static func filePanels(in settings: NSWindow,destination: URL,checks: inout [String:Bool]) async throws -> [[String:Any]] {
        let defaults = UserDefaults.standard,domain = PocketDefaults.domain
        let ownerWindowID = settings.windowNumber
        let original = defaults.persistentDomain(forName: domain)
        let originalInterval = PocketApplicationState.shared.model.refreshSeconds
        defer {
            if let original { defaults.setPersistentDomain(original,forName: domain) }
            else { defaults.removePersistentDomain(forName: domain) }
            PocketApplicationState.shared.model.refreshSeconds = originalInterval
        }
        let directory = destination.appendingPathComponent("real-transfer-"+UUID().uuidString,isDirectory: true)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let codes: [UInt16] = [48,50,49,122,120,99,118,96,97]
        var shortcuts = codes.enumerated().map { index,code in
            var value = SwitcherShortcut(keyCode: code,modifiers: index == 0 ? [.control,.option] : .option)
            value.releaseBehavior = [.choose,.hold,.search][index%3]
            value.presentation.style = [.thumbnails,.icons,.titles][index%3]
            value.presentation.showBadges = index.isMultiple(of: 2)
            value.presentation.autoSize = !index.isMultiple(of: 2)
            return value
        }
        shortcuts[0].holdModifiers = .option
        var bindings = SwitcherActionBinding.defaults
        bindings[4].keyCode = 7
        let rules = [SwitcherExceptionRule(target: .bundlePrefix,value: "org.macpocket.TransferFixture.",visibility: .titleContains,titlePatterns: ["Draft"],shortcuts: .fullscreen)]
        let profiles = try JSONEncoder().encode(shortcuts),actions = try JSONEncoder().encode(bindings),exceptions = try JSONEncoder().encode(rules)
        defaults.set(profiles,forKey: SwitcherShortcutStore.key)
        defaults.set(actions,forKey: SwitcherActionBindings.key)
        defaults.set(exceptions,forKey: SwitcherExceptionStore.key)
        defaults.set(false,forKey: "switcher.globalEnabled")
        defaults.set(false,forKey: "switcher.showBadges")
        defaults.set(5.0,forKey: "MacPocket.refreshSeconds")
        var evidence: [[String:Any]] = []
        let baseline = SettingsTransfer.currentValues(defaults,domain: domain)
        let cancelURL = directory.appendingPathComponent("cancel-export.json")
        let cancelledExport = await drivePanel(button: "Dışa Aktar…",in: settings,url: cancelURL,kind: .save,cancel: true)
        evidence.append(cancelledExport.evidence)
        checks["transferRealSaveCancelDoesNotWriteFileOrChangeSettings"] = cancelledExport.observed && !cancelledExport.timedOut && !FileManager.default.fileExists(atPath: cancelURL.path)
            && NSDictionary(dictionary: baseline).isEqual(to: SettingsTransfer.currentValues(defaults,domain: domain))
        let url = directory.appendingPathComponent("export-nine-profiles.json")
        let exported = await drivePanel(button: "Dışa Aktar…",in: settings,url: url,kind: .save,cancel: false)
        evidence.append(exported.evidence)
        checks["transferRealSavePanelUsesJSONAndWritesChosenFile"] = exported.observed && !exported.timedOut && exported.jsonOnly && exported.selectedURL == url && FileManager.default.fileExists(atPath: url.path)
        guard checks["transferRealSavePanelUsesJSONAndWritesChosenFile"] == true else { return evidence }
        let exportedValues = try SettingsTransfer.importValues(from: SettingsTransfer.readImportData(from: url))
        checks["transferRealExportContainsAllNineProfilesActionsAndExceptions"] = exportedValues[SwitcherShortcutStore.key] as? Data == profiles
            && exportedValues[SwitcherActionBindings.key] as? Data == actions && exportedValues[SwitcherExceptionStore.key] as? Data == exceptions
        defaults.set(try JSONEncoder().encode([SwitcherShortcut.defaultOptionTab]),forKey: SwitcherShortcutStore.key)
        defaults.set(true,forKey: "switcher.showBadges")
        let beforeCancel = SettingsTransfer.currentValues(defaults,domain: domain)
        let cancelledImport = await drivePanel(button: "İçe Aktar…",in: settings,url: url,kind: .open,cancel: true)
        evidence.append(cancelledImport.evidence)
        checks["transferRealOpenCancelPreservesExistingSettings"] = cancelledImport.observed && !cancelledImport.timedOut
            && NSDictionary(dictionary: beforeCancel).isEqual(to: SettingsTransfer.currentValues(defaults,domain: domain))
        let imported = await drivePanel(button: "İçe Aktar…",in: settings,url: url,kind: .open,cancel: false)
        evidence.append(imported.evidence)
        checks["transferRealOpenPanelSelectsOneJSONFile"] = imported.observed && !imported.timedOut && imported.jsonOnly && imported.selectedURL == url && imported.singleFile
        checks["transferRealImportRestoresAllNineProfilesAndHoldSemantics"] = defaults.data(forKey: SwitcherShortcutStore.key) == profiles && SwitcherShortcutStore.load(defaults) == shortcuts
        checks["transferRealImportRestoresActionsExceptionsAndDisabledGlobalKeys"] = defaults.data(forKey: SwitcherActionBindings.key) == actions
            && defaults.data(forKey: SwitcherExceptionStore.key) == exceptions && !defaults.bool(forKey: "switcher.globalEnabled") && !defaults.bool(forKey: "switcher.showBadges")
        checks["transferRealImportUpdatesLiveModel"] = PocketApplicationState.shared.model.refreshSeconds == 5
        checks["transferRealImportShowsSuccess"] = contains(String(localized: "Ayarlar içe aktarıldı."),in: settings)
        _ = WindowSwitcherRuntimeAudit.snapshot(settings,to: destination.appendingPathComponent("transfer-after-valid-import.png"))
        let corrupt = directory.appendingPathComponent("invalid-profiles.json")
        try JSONSerialization.data(withJSONObject: ["format": SettingsTransfer.format,"version": 1,"values": ["MacPocket.appearance": "light",SwitcherShortcutStore.key: ["$data": "%%%"]]]).write(to: corrupt,options: .atomic)
        let beforeCorrupt = SettingsTransfer.currentValues(defaults,domain: domain)
        let invalid = await drivePanel(button: "İçe Aktar…",in: settings,url: corrupt,kind: .open,cancel: false)
        evidence.append(invalid.evidence)
        checks["transferRealCorruptImportPreservesEveryManagedSetting"] = invalid.selectedURL == corrupt && !invalid.timedOut
            && NSDictionary(dictionary: beforeCorrupt).isEqual(to: SettingsTransfer.currentValues(defaults,domain: domain))
        checks["transferRealCorruptImportShowsLocalizedReason"] = contains(SettingsTransferError.invalidValue(SwitcherShortcutStore.key).localizedDescription,in: settings)
        _ = WindowSwitcherRuntimeAudit.snapshot(settings,to: destination.appendingPathComponent("transfer-after-invalid-import.png"))
        try JSONSerialization.data(withJSONObject: ["refreshSeconds": PocketApplicationState.shared.model.refreshSeconds,"nodes": ToolUIAudit.accessibilityNodes(settings)],options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("settings-after-import.json"),options: .atomic)
        defaults.set(try JSONEncoder().encode([SwitcherShortcut.defaultOptionTab]),forKey: SwitcherShortcutStore.key)
        let beforeClose = SettingsTransfer.currentValues(defaults,domain: domain)
        let closed = await drivePanel(button: "İçe Aktar…",in: settings,url: url,kind: .open,cancel: false,closeOwner: true)
        evidence.append(closed.evidence)
        checks["transferRealClosingSettingsCancelsSelectedImport"] = closed.observed && !closed.timedOut && !settings.isVisible
            && NSDictionary(dictionary: beforeClose).isEqual(to: SettingsTransfer.currentValues(defaults,domain: domain))
        checks["transferRealFilePanelsComplete"] = evidence.count == 6 && evidence.allSatisfy { $0["observed"] as? Bool == true && $0["timedOut"] as? Bool == false }
        checks["transferRealFilePanelsBelongToSettingsWindow"] = evidence.allSatisfy { $0["sheetParentID"] as? Int == ownerWindowID }
        return evidence
    }
    private static func contains(_ text: String,in window: NSWindow) -> Bool { WindowSwitcherRuntimeAudit.accessibilityValues(window).contains { $0.contains(text) } }
    private static func drivePanel(button: String.LocalizationValue,in settings: NSWindow,url: URL,kind: TransferFilePanelDriver.Kind,cancel: Bool,closeOwner: Bool = false) async -> TransferFilePanelDriver {
        let driver = TransferFilePanelDriver(url: url,kind: kind,cancel: cancel,closeOwner: closeOwner)
        driver.start()
        let pressed = SwitcherAppearanceRuntimeAudit.press(String(localized: button),in: settings,role: .button)
        if pressed {
            while !driver.finished { try? await Task.sleep(for: .milliseconds(30)) }
            await settle()
        }
        driver.stop()
        return driver
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(140)) }
}

/// Coordinates this isolated process's real file panel. Production creates the panel and performs
/// I/O; a trusted companion controls only its attached sheet, with a finite deadline.
@MainActor fileprivate final class TransferFilePanelDriver {
    enum Kind { case save,open }
    let url: URL,kind: Kind,cancel: Bool,closeOwner: Bool
    private var timer: Timer?,panel: NSSavePanel?,deadline = ContinuousClock.now,appearedAt = ContinuousClock.now
    private var submitted = false,selectionAttempted = false,configuredBeforePresentation = false
    private let token = UUID().uuidString
    private var deadlineWall = Date().timeIntervalSince1970
    private(set) var observed = false,timedOut = false,finished = false,jsonOnly = false,singleFile = true
    private(set) var selectedURL: URL?
    private(set) var sheetParentID: Int?
    init(url: URL,kind: Kind,cancel: Bool,closeOwner: Bool) { self.url = url;self.kind = kind;self.cancel = cancel;self.closeOwner = closeOwner }
    var evidence: [String:Any] { ["kind": kind == .save ? "NSSavePanel" : "NSOpenPanel","cancel": cancel,"closeOwner": closeOwner,"observed": observed,"timedOut": timedOut,"selectedFile": selectedURL?.lastPathComponent ?? "","jsonOnly": jsonOnly,"singleFile": singleFile,"pathConfiguredBeforePresentation": configuredBeforePresentation,"sheetParentID": sheetParentID ?? -1] }
    func prepareBeforePresentation(_ panel: NSSavePanel) {
        guard self.panel == nil,!panel.isVisible,(kind == .open ? panel is NSOpenPanel : !(panel is NSOpenPanel)) else { return }
        self.panel = panel
        configuredBeforePresentation = true
        panel.directoryURL = url.deletingLastPathComponent()
        if kind == .save { panel.nameFieldStringValue = url.lastPathComponent }
        journal("configured")
    }
    func start() {
        SwitcherTransferRuntimeAudit.panelDriver = self
        deadline = .now + .seconds(12)
        deadlineWall = Date().timeIntervalSince1970+12
        let timer = Timer(timeInterval: 0.05,repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        self.timer = timer
        RunLoop.main.add(timer,forMode: .common)
        RunLoop.main.add(timer,forMode: .modalPanel)
    }
    func stop() { timer?.invalidate();timer = nil;if SwitcherTransferRuntimeAudit.panelDriver === self { SwitcherTransferRuntimeAudit.panelDriver = nil } }
    private func tick() {
        if finished { stop();return }
        if ContinuousClock.now >= deadline {
            timedOut = true
            finished = true
            journal("timed-out")
            if let panel { panel.cancel(nil);panel.orderOut(nil) }
            if let modal = NSApp.modalWindow { NSApp.stopModal(withCode: .cancel);modal.orderOut(nil) }
            stop()
            return
        }
        guard let panel else { return }
        if observed,!panel.isVisible { selectedURL = panel.url;finished = true;journal("finished");self.panel = nil;stop();return }
        guard panel.isVisible else { return }
        if !observed { observed = true;appearedAt = .now;sheetParentID = panel.sheetParent?.windowNumber;journal("visible");return }
        guard appearedAt.duration(to: .now) >= .milliseconds(400) else { return }
        jsonOnly = panel.allowedContentTypes == [.json]
        if let open = panel as? NSOpenPanel { singleFile = !open.allowsMultipleSelection && open.canChooseFiles && !open.canChooseDirectories }
        if cancel,!submitted { submitted = true;journal("cancel");return }
        if !submitted,kind == .open,let open = panel as? NSOpenPanel {
            if open.urls.contains(url) {
                submitted = true
                journal(closeOwner ? "close-owner" : "accept")
                if closeOwner { panel.sheetParent?.close() }
                return
            }
            if !selectionAttempted {
                selectionAttempted = true
                journal("select-file")
            }
            return
        }
        if !submitted { submitted = true;journal("accept") }
    }
    private func journal(_ phase: String) {
        var record = evidence
        record["phase"] = phase
        record["hostPID"] = getpid()
        record["hostLaunch"] = NSRunningApplication.current.launchDate?.timeIntervalSince1970 ?? 0
        record["panelWindowID"] = panel?.windowNumber ?? -1
        record["token"] = token
        record["deadline"] = deadlineWall
        record["filePath"] = url.path
        record["prompt"] = panel?.prompt ?? ""
        if let modal = NSApp.modalWindow,!(modal is NSSavePanel) { record["ownedModalNodes"] = ToolUIAudit.accessibilityNodes(modal) }
        guard let data = try? JSONSerialization.data(withJSONObject: record,options: [.prettyPrinted,.sortedKeys]) else { return }
        try? data.write(to: url.deletingLastPathComponent().appendingPathComponent("driver-\(kind == .save ? "save" : "open")-\(cancel ? "cancel" : "accept").json"),options: .atomic)
    }
}
#endif
