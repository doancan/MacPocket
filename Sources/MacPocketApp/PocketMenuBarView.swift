import AppKit
import MacPocketCore
import SwiftUI

/// What a popover shows: the grouped item's tabbed view, or one separate module.
enum MenuBarPopoverContent: Equatable {
    case grouped
    case module(MenuBarModule)
}

/// Popover root. Created when the popover opens and released when it closes, so nothing here
/// re-renders while the popover is hidden.
struct PocketMenuBarView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var history: MenuBarHistory
    @ObservedObject private var store = MenuBarSettingsStore.shared
    let content: MenuBarPopoverContent

    @AppStorage("MacPocket.appearance") private var appearance = PocketAppearance.defaultValue
    @AppStorage("MacPocket.menubar.selectedTab") private var storedTab = MenuBarModule.cpu.rawValue
    @State private var selection: MenuBarModule
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

    private var tabs: [GlassTab<MenuBarModule>] {
        store.preferences.order.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol, tint: $0.tint) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            if content == .grouped {
                GlassTabBar(tabs: tabs, selection: $selection)
                    .background { GlassTabKeyboardShortcuts(tabs: tabs, selection: $selection) }
            }
            MenuBarModuleDetail(module: module, model: model, history: history, binaryUnits: store.preferences.binaryUnits)
                .id(module)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 4)))
            footer
        }
        .padding(PocketSpacing.m)
        .frame(width: Self.width)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear { updateProcessSampling() }
        .onChange(of: selection) { _, value in
            storedTab = value.rawValue
            updateProcessSampling()
        }
        .onDisappear { model.menuBarProcessesWanted = false }
    }

    /// Process sampling is costly; it runs only while a process list is on screen.
    private func updateProcessSampling() {
        let wanted = module.showsProcesses
        let wasWanted = model.menuBarProcessesWanted
        model.menuBarProcessesWanted = wanted
        if wanted && !wasWanted && !model.paused {
            Task { await model.refresh(includeProcesses: true) }
        }
    }

    private var footer: some View {
        HStack(spacing: PocketSpacing.s) {
            Circle()
                .fill(model.paused ? Color.orange : PocketTheme.disk)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Group {
                if model.paused {
                    Text("İzleme duraklatıldı")
                } else if let date = model.lastUpdate {
                    Text("Son ölçüm \(date.formatted(date: .omitted, time: .standard))")
                } else {
                    Text("İlk ölçüm bekleniyor")
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: PocketSpacing.s)
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
