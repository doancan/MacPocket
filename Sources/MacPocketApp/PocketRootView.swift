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
    @AppStorage(PocketPreferenceKey.sidebarIcons) private var sidebarIcons = PocketSidebarIconStyle.standard
    /// SwiftUI keeps a closed `Window`'s views alive, and they kept re-rendering every sample; the page is
    /// rebuilt when the window opens again.
    @State private var windowOpen = true
    @State private var sidebarSearch = ""
    @State private var sidebarSearchFocused = false

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
                    if !sidebarSearch.isEmpty {
                        SidebarSearchResults(query: sidebarSearch) { destination in
                            switch destination {
                            case .page(let page): navigation.select(page)
                            case .tool(let id): openCatalogTool(id)
                            }
                            sidebarSearch = ""
                        }
                    } else {
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
                        Section("Bağlantı") {
                            sidebarRow(.network)
                            sidebarRow(.ssh)
                        }
                    }
                }
                .searchable(text: $sidebarSearch, isPresented: $sidebarSearchFocused, placement: .sidebar, prompt: Text("Sayfa veya araç ara"))
                .onReceive(NotificationCenter.default.publisher(for: .pocketSidebarSearch)) { _ in
                    columnVisibility = .all
                    sidebarSearchFocused = true
                }
                .listStyle(.sidebar)
                .navigationTitle("MacPocket")
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .safeAreaInset(edge: .bottom) { PocketSidebarSettingsButton().padding(.horizontal, 10).padding(.bottom, 10) }
            } detail: {
                Group { if windowOpen { destination } else { Color.clear } }
                    // A short crossfade on page/tool changes only; nothing animates while a page is idle.
                    .id(destinationKey)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: destinationKey)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    // One button language everywhere; explicit styles (.plain, .pocketPrimary…) still win.
                    .buttonStyle(.pocketSecondary)
                    .background { PocketBackdrop(tint: navigation.page.tint) }
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
                        if navigation.page != .ssh && navigation.tool != .practical {
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
        .background { MainWindowVisibility(changed: { model.setMainWindowVisible($0) }, opened: { windowOpen = $0 })
            .frame(width: 1, height: 1).allowsHitTesting(false) }
        .onAppear {
            let windowAction = openWindow, settingsAction = openSettings
            AIUsageIntegration.shared.openSettingsWindow = {
                windowAction(id: "ai-usage")
                NSApp.activate(ignoringOtherApps: true)
            }
            model.openMainWindow = { showPocketWindow(windowAction) }
            model.openSettingsWindow = { settingsAction(); NSApp.activate(ignoringOtherApps: true) }
            if !PocketLaunch.handledFirstWindow {
                PocketLaunch.handledFirstWindow = true
                #if DEBUG
                if CommandLine.arguments.contains("--open-ai-usage") { openWindow(id: "ai-usage") }
                #endif
                // First run (or a relaunch in the middle of granting permissions): the setup wizard comes
                // first.
                if OnboardingRecord.needsPresentation() {
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                // "Show main window at launch" off: SwiftUI always creates the window, so close it right
                // away. The open action captured above keeps working for the menu bar and the Dock icon.
                if !PocketLaunch.showsWindow { dismissWindow(id: "main"); return }
            }
            Task { await model.refresh() }
        }
        .onDisappear { model.setMainWindowVisible(false) }
    }

    private func sidebarRow(_ page: PocketPage) -> some View {
        HStack(spacing: 10) {
            PocketSidebarIcon(symbol: page.icon, tint: page.tint, size: 24, style: sidebarIcons)
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
        case .network: NetworkManagementView(model: model)
        case .tools:
            if let module = navigation.tool?.module, !modules.available.contains(module) {
                DisabledModuleView(module: module)
            } else {
                switch navigation.tool {
                case .practical:
                    #if DEBUG
                    PracticalToolsView(workspace: ToolUIAudit.practicalWorkspace ?? .shared)
                    #else
                    PracticalToolsView()
                    #endif
                case .similarImages: SimilarImagesView()
                case .screenCleaning: ScreenCleaningView()
                case .taskManager: TaskManagerView(model: model)
                case .diagnostics: SystemToolsView()
                case .windowSwitcher: WindowSwitcherView()
                case .hiddenSettings: HiddenSettingsView()
                case .clipboard: ClipboardHistoryView()
                case .windowLayout: WindowLayoutView()
                case .quickActions: QuickActionsView()
                case .quitGuard: QuitGuardView()
                case .brightness: DisplayBrightnessView()
                case .freezer: AppFreezerView()
                case .screenGrab: ScreenGrabView()
                case .mouseScroll: MouseScrollView()
                case .mouseButtons: MouseButtonsView()
                case .audio: AudioOutputView()
                case .mixer: VolumeMixerView()
                case .recorder: ScreenRecorderView()
                case .screenshot: ScreenshotView()
                case .bluetoothBattery: BluetoothBatteryView()
                case .displays: DisplaySettingsView()
                case .peripherals: PeripheralsView()
                case .usbEject: USBEjectView()
                case .diskHealth: DiskHealthView()
                case .systemData: SystemDataView(model: .shared)
                case .powerSchedule: PowerScheduleView()
                case .startupItems: StartupItemsView()
                case .maintenance: MaintenanceView()
                case .commandBar: CommandBarSettingsView()
                case .shelf: ShelfSettingsView()
                case .dockPreview: DockPreviewSettingsView()
                case .menuBarOrganizer: MenuBarOrganizerView()
                case .cableImpact: CableImpactView()
                case .none: ToolsHubView(model: model, openTool: openCatalogTool)
                }
            }
        }
    }

    private func openCatalogTool(_ id: String) { model.openCatalogTool(id) }

}

/// A sidebar row's icon, following Ayarlar → Kenar çubuğu simgeleri.
private struct PocketSidebarIcon: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    let style: PocketSidebarIconStyle

    var body: some View {
        switch style {
        case .colorful: PocketIconTile(symbol: symbol, tint: tint, size: size)
        case .monochrome:
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

/// Bottom of the sidebar: Settings, styled like a sidebar row.
private struct PocketSidebarSettingsButton: View {
    @AppStorage(PocketPreferenceKey.sidebarIcons) private var sidebarIcons = PocketSidebarIconStyle.standard
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            HStack(spacing: PocketSpacing.s) {
                PocketSidebarIcon(symbol: "gearshape.fill", tint: Color(hex: 0x8E8E93), size: 22, style: sidebarIcons)
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
                Text("1 saniye").tag(1.0)
                Text("2 saniye").tag(2.0)
                Text("5 saniye").tag(5.0)
                Text("10 saniye").tag(10.0)
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
            Button("Sayfa veya Araç Ara…") {
                showPocketWindow(openWindow)
                NotificationCenter.default.post(name: .pocketSidebarSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .help) {
            Button("MacPocket Yardımı") { NSWorkspace.shared.open(PocketLinks.help) }
            Button("Değişiklik Günlüğü") { NSWorkspace.shared.open(PocketLinks.changelog) }
            Divider()
            Button("Sorun Bildir…") { NSWorkspace.shared.open(PocketLinks.issues) }
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
                Text("1 saniye").tag(1.0)
                Text("2 saniye").tag(2.0)
                Text("5 saniye").tag(5.0)
                Text("10 saniye").tag(10.0)
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

/// Public pages the Help menu opens; the project's README is the user guide.
enum PocketLinks {
    static let repository = URL(string: "https://github.com/doancan/MacPocket")!
    static let help = repository.appending(path: "blob/main/README.md")
    static let changelog = repository.appending(path: "blob/main/CHANGELOG.md")
    static let issues = repository.appending(path: "issues/new")
}
