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

    @AppStorage("MacPocket.menubar.selectedTab") private var storedTab = MenuBarModule.cpu.rawValue
    @State private var selection: MenuBarModule
    @State private var showsSSH = false
    @PocketReduceMotion private var reduceMotion

    init(model: PocketModel, history: MenuBarHistory, content: MenuBarPopoverContent) {
        self.model = model
        self.history = history
        self.content = content
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
        let enabled = store.preferences.enabledModules
        return enabled.isEmpty ? store.preferences.order : enabled
    }

    private var tabs: [GlassTab<MenuBarModule>] {
        tabModules.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol, tint: $0.tint) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            if content == .grouped {
                GlassTabBar(tabs: tabs, selection: $selection, showsShortcutHints: true, showsTitles: false)
                    .background { GlassTabKeyboardShortcuts(tabs: tabs, selection: $selection) }
            }
            MenuBarModuleDetail(module: module, model: model, history: history, binaryUnits: store.preferences.binaryUnits)
                .id(module)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 4)))
            footer
        }
        .padding(PocketSpacing.m)
        .frame(width: Self.width)
        .background { PocketPopoverBackdrop() }
        .tint(PocketTheme.accent)
        .environment(\.pocketTint, PocketTheme.brand)
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
        HStack(spacing: PocketSpacing.s) {
            Spacer(minLength: PocketSpacing.s)
            footerButton("SSH Hızlı Bağlan", symbol: "terminal") { showsSSH.toggle() }
                .popover(isPresented: $showsSSH) {
                    SSHQuickConnectView { showsSSH = false }
                }
            footerButton("MacPocket’ı aç", symbol: "macwindow") { model.openMainWindow?() }
                .keyboardShortcut("0", modifiers: .command)
            footerButton("Ayarlar", symbol: "gearshape") { model.openSettingsWindow?() }
                .keyboardShortcut(",", modifiers: .command)
            footerButton(model.paused ? "İzlemeyi sürdür" : "İzlemeyi duraklat",
                         symbol: model.paused ? "play.fill" : "pause.fill") { model.paused.toggle() }
            footerButton("MacPocket’tan çık", symbol: "power") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.top, PocketSpacing.xxs)
    }

    private func footerButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarFooterButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The chosen app theme behind the popover: its opaque canvas tone with a soft wash of the brand colors, so the Stats Bar
/// dropdown matches the main window and stays readable over any window behind it (no translucency).
private struct PocketPopoverBackdrop: View {
    var body: some View {
        ZStack {
            PocketTheme.background
            RadialGradient(colors: [PocketTheme.brand.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 360)
            RadialGradient(colors: [PocketTheme.brandSecondary.opacity(0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 280)
        }
        .accessibilityHidden(true)
    }
}

/// Borderless icon button with a hover/press highlight, like Control Center's small buttons.
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
                .foregroundStyle(hovering ? .primary : .secondary)
                .background(Color.primary.opacity(pressed ? 0.14 : hovering ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
