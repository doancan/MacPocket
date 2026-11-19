import AppKit
import MacPocketCore
import MacPocketSSH
import SwiftUI

/// What a popover shows: the grouped item's tabbed view, or one separate module.
enum MenuBarPopoverContent: Equatable {
    case grouped
    case module(MenuBarModule)
}

/// Popover root. Created when the popover opens and released when it closes, so nothing here
/// re-renders while the popover is hidden.
struct PocketMenuBarView: View {
    var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    @ObservedObject private var store = MenuBarSettingsStore.shared
    let content: MenuBarPopoverContent
    /// Closes the popover (a clipboard paste must reach the app in front).
    var close: @MainActor () -> Void = {}

    @AppStorage("MacPocket.menubar.selectedTab") private var storedTab = MenuBarModule.cpu.rawValue
    @State private var selection: MenuBarModule
    @State private var showsSSH = false
    @PocketReduceMotion private var reduceMotion

    init(model: PocketModel, history: MenuBarHistory, content: MenuBarPopoverContent, close: @escaping @MainActor () -> Void = {}) {
        self.model = model
        self.history = history
        self.content = content
        self.close = close
        // Reopen on the last tab without a first frame on the default tab.
        let stored = UserDefaults.standard.string(forKey: "MacPocket.menubar.selectedTab") ?? ""
        _selection = State(initialValue: MenuBarModule(rawValue: stored) ?? .cpu)
    }

    static let width: CGFloat = 368

    private var module: MenuBarModule {
        if case let .module(module) = content { return module }
        return selection
    }

    /// The enabled modules, in menu bar order; with none enabled the popover still offers every module.
    private var tabModules: [MenuBarModule] {
        let enabled = store.preferences.enabledModules.filter(\.isRuntimeAvailable)
        return enabled.isEmpty ? store.preferences.order.filter(\.isRuntimeAvailable) : enabled
    }

    private var tabs: [GlassTab<MenuBarModule>] {
        tabModules.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol, tint: $0.tint) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            if content == .grouped {
                MenuBarTabStrip(tabs: tabs, selection: $selection)
                    .background { GlassTabKeyboardShortcuts(tabs: tabs, selection: $selection) }
            }
            MenuBarModuleDetail(module: module, model: model, history: history, binaryUnits: store.preferences.binaryUnits,
                                showsTitle: content != .grouped)
                .id(module)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 4)))
            Divider().padding(.horizontal, -PocketSpacing.m)
            footer
        }
        .padding(PocketSpacing.m)
        .frame(width: Self.width)
        .tint(PocketTheme.accent)
        .environment(\.pocketTint, PocketTheme.brand)
        .environment(\.closeMenuBarPopover, close)
        .onAppear {
            keepSelectionOnAVisibleTab()
            updateProcessSampling()
        }
        .onChange(of: tabModules) { keepSelectionOnAVisibleTab() }
        .onChange(of: selection) { _, value in
            storedTab = value.rawValue
            updateProcessSampling()
        }
        .onDisappear { model.menuBarProcessesWanted = false }
    }

    /// A module switched off since the popover last opened has no tab; fall back to the first one.
    private func keepSelectionOnAVisibleTab() {
        guard !tabModules.contains(selection), let first = tabModules.first else { return }
        selection = first
    }

    /// Process sampling is costly; it runs only while a process list is on screen.
    private func updateProcessSampling() {
        let wanted = module.showsProcesses
        let wasWanted = model.menuBarProcessesWanted
        model.menuBarProcessesWanted = wanted
        if wanted && !wasWanted && !model.paused {
            Task { await model.refresh() }
        }
    }

    private var footer: some View {
        HStack(spacing: PocketSpacing.xs) {
            Button { model.openMainWindow?() } label: {
                Label("MacPocket’ı aç", systemImage: "macwindow")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, PocketSpacing.s)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MenuBarFooterButtonStyle())
            .keyboardShortcut("0", modifiers: .command)
            .help("MacPocket’ı aç (⌘0)")
            if model.paused {
                Label("Duraklatıldı", systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("İzleme duraklatıldı")
            }
            Spacer(minLength: PocketSpacing.s)
            footerButton("SSH Hızlı Bağlan", symbol: "terminal") { showsSSH.toggle() }
                .popover(isPresented: $showsSSH) {
                    SSHQuickConnectView { showsSSH = false }
                }
            footerButton(model.paused ? "İzlemeyi sürdür" : "İzlemeyi duraklat",
                         symbol: model.paused ? "play.fill" : "pause.fill") { model.paused.toggle() }
            footerButton("Ayarlar", symbol: "gearshape") { model.openSettingsWindow?() }
                .keyboardShortcut(",", modifiers: .command)
            footerButton("MacPocket’tan çık", symbol: "power") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func footerButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarFooterButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Borderless button with a hover/press highlight, like Control Center's small buttons. Labels stay `.primary`:
/// on the glass popover, secondary text falls below a readable contrast.
private struct MenuBarFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed) { configuration.label }
    }

    private struct HoverHighlight<Label: View>: View {
        let pressed: Bool
        @ViewBuilder var label: () -> Label
        @State private var hovering = false

        var body: some View {
            label()
                .foregroundStyle(.primary)
                .background(Color.primary.opacity(pressed ? 0.14 : hovering ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: PocketRadius.small + 1, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
