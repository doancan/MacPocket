import AppKit
import MacPocketCore
import ServiceManagement
import SwiftUI

struct PocketRootView: View {
    let model: PocketModel
    @ObservedObject private var navigation: PocketNavigation
    @State private var utility = MacUtility.timeMachine
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
                    }
                    Section("Bakım") {
                        sidebarRow(.cleanup)
                        sidebarRow(.storage)
                        sidebarRow(.applications)
                    }
                    Section("Araçlar") { sidebarRow(.tools) }
                }
                .listStyle(.sidebar)
                .navigationTitle("MacPocket")
                .navigationSplitViewColumnWidth(220)
                .safeAreaInset(edge: .bottom) { PocketSidebarStatus(model: model).padding(12) }
            } detail: {
                destination
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .background(PocketTheme.background)
                    .navigationTitle(navigation.title)
                    .navigationSubtitle("MacPocket")
                    .toolbar(id: "MacPocket.main") {
                        ToolbarItem(id: "back", placement: .navigation) {
                            if navigation.tool != nil {
                                Button { navigation.select(.tools) } label: { Label("Tools’a Dön", systemImage: "chevron.left") }
                                    .help("Tools’a dön (⌘[)")
                            }
                        }
                        ToolbarItem(id: "refresh", placement: .primaryAction) { PocketRefreshButton(model: model) }
                        ToolbarItem(id: "pause", placement: .primaryAction) { PocketPauseButton(model: model) }
                        ToolbarItem(id: "interval", placement: .primaryAction) { PocketIntervalMenu(model: model) }
                        ToolbarItem(id: "settings", placement: .primaryAction) {
                            SettingsLink { Label("Ayarlar", systemImage: "gearshape") }.help("Ayarlar (⌘,)")
                        }
                    }
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
        }
        .frame(minWidth: 1100, minHeight: 740)
        .onAppear {
            let windowAction = openWindow, settingsAction = openSettings
            model.openMainWindow = { showPocketWindow(windowAction) }
            model.openSettingsWindow = { settingsAction(); NSApp.activate(ignoringOtherApps: true) }
            model.mainWindowVisible = true
            Task { await model.refresh() }
        }
        .onDisappear { model.mainWindowVisible = false }
    }

    private func sidebarRow(_ page: PocketPage) -> some View {
        Label(page.rawValue, systemImage: page.icon).tag(page).padding(.vertical, 4)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { navigation.select(page) })
    }

    @ViewBuilder private var destination: some View {
        switch navigation.page {
        case .overview: OverviewView(model: model, files: model.cleanup, applications: model.applications, navigation: navigation)
        case .performance: PerformanceView(model: model)
        case .power: PowerManagementView(model: model)
        case .cleanup: FileWorkspaceView(model: model.cleanup, cleanup: true)
        case .storage: FileWorkspaceView(model: model.storage)
        case .applications: ApplicationsView(model: model.applications)
        case .tools:
            switch navigation.tool {
            case .similarImages: SimilarImagesView()
            case .screenCleaning: ScreenCleaningView()
            case .utilities: MacUtilitiesView(initialTool: utility).id(utility)
            case .leftovers: ApplicationLeftoversView()
            case .taskManager: TaskManagerView(model: model)
            case .diagnostics: SystemToolsView()
            case .windowSwitcher: WindowSwitcherView()
            case .none: ToolsHubView(sleepController: model.sleepController, openTool: openCatalogTool)
            }
        }
    }

    private func openCatalogTool(_ id: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch id {
        case "similar-images": navigation.open(.similarImages)
        case "screen-cleaning": navigation.open(.screenCleaning)
        case "app-leftovers": navigation.open(.leftovers)
        case "mac-utilities", "time-machine": utility = .timeMachine; navigation.open(.utilities)
        case "launch-jobs": utility = .launchJobs; navigation.open(.utilities)
        case "listening-ports": utility = .listeningPorts; navigation.open(.utilities)
        case "disk-info": utility = .diskInfo; navigation.open(.utilities)
        case "spotlight": utility = .spotlight; navigation.open(.utilities)
        case "dns": utility = .dns; navigation.open(.utilities)
        case "routes": utility = .routes; navigation.open(.utilities)
        case "os-updates": utility = .updateHistory; navigation.open(.utilities)
        case "security": utility = .systemIntegrity; navigation.open(.utilities)
        case "permissions": NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        case "task-manager": navigation.open(.taskManager)
        case "system-reports", "maintenance": navigation.open(.diagnostics)
        case "window-switcher": navigation.open(.windowSwitcher)
        case "uninstaller": model.applications.showUpdates = false; navigation.select(.applications)
        case "app-updater": model.applications.showUpdates = true; navigation.select(.applications)
        case "downloads": model.storage.useRoot(home.appendingPathComponent("Downloads")); navigation.select(.storage)
        case "duplicates": model.storage.scope = .duplicates; navigation.select(.storage)
        case "large-old": model.storage.scope = .old; navigation.select(.storage)
        case "system-junk": model.cleanup.useRoot(home.appendingPathComponent("Library/Caches"), scope: .folders); navigation.select(.cleanup)
        case "trash": model.storage.useRoot(home.appendingPathComponent(".Trash"), scope: .folders); navigation.select(.storage)
        case "login-items", "background-items": SMAppService.openSystemSettingsLoginItems()
        default: break
        }
    }
}

private struct PocketSidebarStatus: View {
    @ObservedObject var model: PocketModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.paused ? "İzleme duraklatıldı" : "Canlı sistem verisi", systemImage: model.paused ? "pause.circle" : "waveform.path.ecg")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(model.paused ? Color.orange : PocketTheme.disk)
            if let date = model.lastUpdate {
                Text("Son ölçüm \(date.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .leading)
        .padding(12).pocketGlass()
    }
}

private struct PocketRefreshButton: View {
    @ObservedObject var model: PocketModel
    var body: some View {
        Button { Task { await model.refresh() } } label: { Label("Şimdi Yenile", systemImage: "arrow.clockwise") }.help("Şimdi yenile (⌘R)")
    }
}
private struct PocketPauseButton: View {
    @ObservedObject var model: PocketModel
    var body: some View {
        Button { model.paused.toggle() } label: {
            Label(model.paused ? "İzlemeyi Sürdür" : "İzlemeyi Duraklat", systemImage: model.paused ? "play" : "pause")
        }.help("İzlemeyi duraklat/sürdür (⇧⌘P)")
    }
}
private struct PocketIntervalMenu: View {
    @ObservedObject var model: PocketModel
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
    @ObservedObject var model: PocketModel
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
        CommandGroup(after: .textEditing) {
            Button("Ara…") { NotificationCenter.default.post(name: .pocketFind, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Git") {
            Button("Hızlı Bakışı Göster") { NotificationCenter.default.post(name: .pocketQuickLook, object: nil) }
                .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(!showMenuBar)
            Divider()
            ForEach(Array(PocketPage.allCases.enumerated()), id: \.element.id) { index, page in
                Button(page.rawValue) { navigation.select(page); showPocketWindow(openWindow) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Görev Yöneticisi") { navigation.open(.taskManager); showPocketWindow(openWindow) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Tools’a Dön") { navigation.select(.tools) }.keyboardShortcut("[", modifiers: .command).disabled(navigation.tool == nil)
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
