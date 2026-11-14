import AppKit
import MacPocketCore
import SwiftUI

struct PocketRootView: View {
    let model: PocketModel
    @ObservedObject private var modules = PocketModuleRuntime.shared
    @ObservedObject private var navigation: PocketNavigation
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow
    @PocketReduceMotion private var reduceMotion
    @AppStorage(PocketPreferenceKey.sidebarIcons) private var sidebarIcons = PocketSidebarIconStyle.colorful

    private var destinationKey: String { navigation.page.rawValue + "/" + (navigation.tool?.rawValue ?? "") }

    init(model: PocketModel) {
        self.model = model
        navigation = model.navigation
    }

    var body: some View {
        GeometryReader { bounds in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(selection: Binding<PocketPage?>(get: { navigation.page }, set: {
                    if let value = $0 { navigation.select(value) }
                })) {
                    Section("Mac’in") {
                        sidebarRow(.overview)
                        sidebarRow(.performance)
                        sidebarRow(.power)
                        sidebarRow(.menuBar)
                    }
                    Section("Bakım") {
                        sidebarRow(.cleanup)
                        sidebarRow(.storage)
                        sidebarRow(.applications)
                        sidebarRow(.tools)
                    }
                    Section("Üretkenlik") {
                        sidebarRow(.practical)
                        sidebarRow(.ssh)
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .top, spacing: 0) { PocketSidebarBrand() }
                .navigationTitle("MacPocket")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .safeAreaInset(edge: .bottom) { PocketSidebarSettingsButton().padding(.horizontal, 10).padding(.bottom, 10) }
            } detail: {
                destination
                    // A short crossfade on page/tool changes only; nothing animates while a page is idle.
                    .id(destinationKey)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: destinationKey)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    // One button language everywhere; explicit styles (.plain, .pocketPrimary…) still win.
                    .buttonStyle(.pocketSecondary)
                    .background(PocketBackdrop(tint: navigation.page.tint))
                    .environment(\.pocketTint, navigation.page.tint)
                    .onReceive(NotificationCenter.default.publisher(for: .pocketOpenTool)) { note in
                        if let id = note.object as? String { openCatalogTool(id) }
                    }
                    .navigationTitle(navigation.title)
                    // The page heading already names the page; the toolbar keeps only its buttons and the
                    // backdrop flows under it, so there is no separator line to misalign with the sidebar.
                    .modifier(PocketToolbarChrome())
                    .toolbar(id: "MacPocket.main") {
                        ToolbarItem(id: "back", placement: .navigation) {
                            if navigation.tool != nil {
                                Button { navigation.select(.tools) } label: { Label("Araçlara Dön", systemImage: "chevron.left") }
                                    .help("Araçlara dön (⌘[)")
                            }
                        }
                        if navigation.page != .practical && navigation.page != .ssh {
                            ToolbarItem(id: "refresh", placement: .primaryAction) { PocketRefreshButton(model: model) }
                            ToolbarItem(id: "pause", placement: .primaryAction) { PocketPauseButton(model: model) }
                            ToolbarItem(id: "interval", placement: .primaryAction) { PocketIntervalMenu(model: model) }
                            // Monitoring controls share one glass group; Settings sits in its own.
                            ToolbarSpacer(.fixed, placement: .primaryAction)
                        }
                        ToolbarItem(id: "settings", placement: .primaryAction) {
                            SettingsLink { Label("Ayarlar", systemImage: "gearshape") }.help("Ayarlar (⌘,)")
                        }
                    }
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
        }
        .frame(minWidth: 960, minHeight: 620)
        .background(MainWindowVisibility { model.setMainWindowVisible($0) }.frame(width: 1, height: 1).allowsHitTesting(false))
        .onAppear {
            let windowAction = openWindow, settingsAction = openSettings
            AIUsageIntegration.shared.openSettingsWindow = {
                windowAction(id: "ai-usage"); NSApp.activate(ignoringOtherApps: true)
            }
            model.openMainWindow = { showPocketWindow(windowAction) }
            model.openSettingsWindow = { settingsAction(); NSApp.activate(ignoringOtherApps: true) }
            if !PocketLaunch.handledFirstWindow {
                PocketLaunch.handledFirstWindow = true
                #if DEBUG
                if CommandLine.arguments.contains("--open-ai-usage") { openWindow(id: "ai-usage") }
                #endif
                // First run (or a relaunch in the middle of granting permissions): the setup wizard comes first.
                if OnboardingRecord.needsPresentation() {
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                // "Show main window at launch" off: SwiftUI always creates the window, so close it right away.
                // The open action captured above keeps working for the menu bar and the Dock icon.
                if !PocketLaunch.showsWindow { dismissWindow(id: "main"); return }
            }
            Task { await model.refresh() }
        }
        .onDisappear { model.setMainWindowVisible(false) }
    }

    private func sidebarRow(_ page: PocketPage) -> some View {
        HStack(spacing: 10) {
            if page == .ssh {
                SSHManagerIcon(size: 24)
            } else {
                switch sidebarIcons {
                case .colorful: PocketIconTile(symbol: page.icon, tint: page.tint, size: 24)
                case .monochrome:
                    Image(systemName: page.icon).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 24, height: 24).accessibilityHidden(true)
                }
            }
            Text(page.localizedTitle).font(.body)
        }
        .tag(page).padding(.vertical, 4)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { navigation.select(page) })
    }

    @ViewBuilder private var destination: some View {
        switch navigation.page {
        case .overview: OverviewView(model: model, files: model.cleanup, applications: model.applications, navigation: navigation)
        case .performance: PerformanceView(model: model)
        case .power: PowerManagementView(model: model)
        case .cleanup: CleanupView(model: model.cleanup.junk)
        case .storage: StorageView(model: model.storage)
        case .applications: ApplicationsView(model: model.applications)
        case .ssh: SSHManagerView()
        case .menuBar: MenuBarStudioView(model: model)
        case .practical:
            #if DEBUG
            PracticalToolsView(workspace: ToolUIAudit.practicalWorkspace ?? .shared)
            #else
            PracticalToolsView()
            #endif
        case .tools:
            if let module = navigation.tool?.module, !modules.available.contains(module) {
                DisabledModuleView(module: module)
            } else {
                switch navigation.tool {
                case .similarImages: SimilarImagesView()
                case .screenCleaning: ScreenCleaningView()
                case .utilities: MacUtilitiesView(initialTool: navigation.utility).id(navigation.utility)
                case .leftovers: ApplicationLeftoversView()
                case .taskManager: TaskManagerView(model: model)
                case .diagnostics: SystemToolsView()
                case .windowSwitcher: WindowSwitcherView()
                case .hiddenSettings: HiddenSettingsView()
                case .clipboard: ClipboardHistoryView()
                case .windowLayout: WindowLayoutView()
                case .speedTest: SpeedTestView()
                case .ports: PortManagerView(model: model)
                case .quickActions: QuickActionsView()
                case .quitGuard: QuitGuardView()
                case .brightness: DisplayBrightnessView()
                case .macros: MacrosView()
                case .freezer: AppFreezerView()
                case .supportReport: SupportReportView(model: model)
                case .focus: FocusSessionView()
                case .workspaces: WorkspacesView()
                case .snippets: SnippetsView()
                case .screenGrab: ScreenGrabView()
                case .mouseScroll: MouseScrollView()
                case .mouseButtons: MouseButtonsView()
                case .audio: AudioOutputView()
                case .mixer: VolumeMixerView()
                case .recorder: ScreenRecorderView()
                case .screenshot: ScreenshotView()
                case .bluetoothBattery: BluetoothBatteryView()
                case .displays: DisplaySettingsView()
                case .networkTraffic: NetworkTrafficView()
                case .peripherals: PeripheralsView()
                case .usbEject: USBEjectView()
                case .diskHealth: DiskHealthView()
                case .systemData: SystemDataView()
                case .wifi: WiFiView()
                case .hosts: HostsView()
                case .screenTime: ScreenTimeView()
                case .localNetwork: LANScannerView()
                case .powerSchedule: PowerScheduleView()
                case .privacy: PrivacyCheckView()
                case .startupItems: StartupItemsView()
                case .maintenance: MaintenanceView()
                case .commandBar: CommandBarSettingsView()
                case .shelf: ShelfSettingsView()
                case .dockPreview: DockPreviewSettingsView()
                case .menuBarOrganizer: MenuBarOrganizerView()
                case .updateCenter: IndependentUpdateCenterView()
                case .internetControl: InternetControlView()
                case .cableImpact: CableImpactView()
                case .none: ToolsHubView(model: model, openTool: openCatalogTool)
                }
            }
        }
    }

    private func openCatalogTool(_ id: String) { model.openCatalogTool(id) }

}

private struct PocketSidebarBrand: View {
    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("MacPocket").font(.headline)
                Text("Bakım ve izleme").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PocketSpacing.l)
        .padding(.top, PocketSpacing.xs)
        .padding(.bottom, PocketSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// Bottom of the sidebar: Settings, styled like a sidebar row.
private struct PocketSidebarSettingsButton: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            HStack(spacing: PocketSpacing.s) {
                PocketIconTile(symbol: "gearshape.fill", tint: Color(hex: 0x8E8E93), size: 22)
                Text("Ayarlar")
                Spacer(minLength: 0)
                Text("⌘,").font(.subheadline).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("MacPocket ayarlarını aç (⌘,)")
    }
}

private struct PocketRefreshButton: View {
    var model: PocketModel
    @State private var refreshCount = 0
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        Button {
            refreshCount += 1
            Task { await model.refresh() }
        } label: {
            Label("Şimdi Yenile", systemImage: "arrow.clockwise")
                .modifier(PocketRefreshSpin(trigger: refreshCount, enabled: !reduceMotion))
        }
        .help("Şimdi yenile (⌘R)")
    }
}

/// One clockwise turn of the refresh glyph per click .
private struct PocketRefreshSpin: ViewModifier {
    let trigger: Int
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.symbolEffect(.rotate.clockwise, options: .speed(1.6), value: trigger)
        } else {
            content
        }
    }
}

private struct PocketPauseButton: View {
    var model: PocketModel
    var body: some View {
        Button { model.paused.toggle() } label: {
            Label(model.paused ? "İzlemeyi Sürdür" : "İzlemeyi Duraklat", systemImage: model.paused ? "play" : "pause")
                .contentTransition(.symbolEffect(.replace))
        }.help("İzlemeyi duraklat/sürdür (⇧⌘P)")
    }
}
private struct PocketIntervalMenu: View {
    @Bindable var model: PocketModel
    var body: some View {
        Menu {
            Picker("Yenileme Aralığı", selection: $model.refreshSeconds) {
                Text("1 saniye").tag(1.0); Text("2 saniye").tag(2.0)
                Text("5 saniye").tag(5.0); Text("10 saniye").tag(10.0)
            }
        } label: { Label("Yenileme Aralığı", systemImage: "timer") }.help("Yenileme aralığı: \(Int(model.refreshSeconds)) saniye")
    }
}

struct PocketCommands: Commands {
    @Bindable var model: PocketModel
    @ObservedObject private var navigation: PocketNavigation
    @Environment(\.openWindow) private var openWindow
    @AppStorage("MacPocket.showMenuBar") private var showMenuBar = true
    init(model: PocketModel) { self.model = model; navigation = model.navigation }

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(replacing: .newItem) {
            Button("MacPocket Penceresini Göster") { showPocketWindow(openWindow) }.keyboardShortcut("0", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Güncellemeleri Denetle…") { UpdateService.shared.checkForUpdates() }
                .disabled(!UpdateService.shared.isAvailable)
        }
        CommandGroup(after: .appSettings) {
            Button("AI Kotaları…") { openWindow(id: "ai-usage"); NSApp.activate(ignoringOtherApps: true) }
            Button("Kurulum Sihirbazı…") { openWindow(id: "onboarding"); NSApp.activate(ignoringOtherApps: true) }
        }
        CommandGroup(after: .textEditing) {
            Button("Ara…") { NotificationCenter.default.post(name: .pocketFind, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Git") {
            Button("Dosya Rafı’nı Aç") {
                if PocketModule.shelf.isAvailable() { ShelfService.shared.show() }
                else { navigation.open(.shelf); showPocketWindow(openWindow) }
            }
            Button("Komut Çubuğu’nu Aç") {
                if PocketModule.commandBar.isAvailable() { CommandBarService.shared.show() }
                else { navigation.open(.commandBar); showPocketWindow(openWindow) }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Hızlı Bakışı Göster") { NotificationCenter.default.post(name: .pocketQuickLook, object: nil) }
                .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(!showMenuBar)
            Divider()
            ForEach(Array(PocketPage.allCases.prefix(9).enumerated()), id: \.element.id) { index, page in
                Button(page.localizedTitle) { navigation.select(page); showPocketWindow(openWindow) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Görev Yöneticisi") { navigation.open(.taskManager); showPocketWindow(openWindow) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Araçlara Dön") { navigation.select(.tools) }.keyboardShortcut("[", modifiers: .command).disabled(navigation.tool == nil)
        }
        CommandMenu("İzleme") {
            Button("Şimdi Yenile") { Task { await model.refresh() } }.keyboardShortcut("r", modifiers: .command)
            Button(model.paused ? "İzlemeyi Sürdür" : "İzlemeyi Duraklat") { model.paused.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Picker("Yenileme Aralığı", selection: $model.refreshSeconds) {
                Text("1 saniye").tag(1.0); Text("2 saniye").tag(2.0)
                Text("5 saniye").tag(5.0); Text("10 saniye").tag(10.0)
            }
            Divider()
            Toggle("Menü Çubuğunda Göster", isOn: $showMenuBar)
        }
    }
}

private struct PocketToolbarChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
