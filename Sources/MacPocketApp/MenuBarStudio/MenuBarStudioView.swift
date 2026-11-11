import MacPocketAIUsage
import MacPocketCore
import SwiftUI

/// Menü Çubuğu: a live preview of the menu bar on top, the modules on the left and the options of the selected
/// module (or the layout-wide options) on the right. Every change applies to the real menu bar immediately.
struct MenuBarStudioView: View {
    @Bindable var model: PocketModel
    @ObservedObject private var navigation: PocketNavigation
    @ObservedObject private var store = MenuBarSettingsStore.shared
    @ObservedObject private var history = MenuBarHistory.shared
    @ObservedObject private var aiUsage = AIUsageService.shared
    @AppStorage(MenuBarPreviewAppearance.storageKey) private var appearance = MenuBarPreviewAppearance.system
    @Environment(\.colorScheme) private var systemScheme
    @State private var pane = MenuBarPane.general

    init(model: PocketModel) {
        self.model = model
        navigation = model.navigation
    }

    private var provider: MenuBarImageProvider {
        MenuBarImageProvider(model: model, preferences: store.preferences, history: history, aiUsage: aiUsage)
    }

    private var surface: MenuBarSurface { MenuBarSurface(dark: appearance.isDark(system: systemScheme)) }

    var body: some View {
        let provider = provider
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "İstatistik Çubuğu",
                              subtitle: "Menü çubuğundaki öğeleri seç, sırala ve her birini istediğin gibi özelleştir; değişiklikler anında uygulanır.",
                              icon: "menubar.rectangle") {
                Toggle("Menü çubuğunda göster", isOn: $store.preferences.visible).toggleStyle(.switch)
            }
            MenuBarPreviewCanvas(provider: provider, pane: $pane)
            HStack(alignment: .top, spacing: PocketSpacing.l) {
                MenuBarModuleList(pane: $pane, store: store, provider: provider)
                    .frame(width: 252)
                inspector(provider)
            }
            .frame(maxHeight: .infinity)
        }
        .pocketPage()
        .onAppear(perform: takeRequestedModule)
        .onChange(of: navigation.menuBarModule) { takeRequestedModule() }
    }

    @ViewBuilder
    private func inspector(_ provider: MenuBarImageProvider) -> some View {
        ScrollView {
            Group {
                switch pane {
                case .general:
                    MenuBarGeneralInspector(model: model, provider: provider, surface: surface, store: store)
                case .module(let module):
                    MenuBarModuleInspector(model: model, module: module, provider: provider, surface: surface, store: store)
                }
            }
            .padding(.bottom, PocketSpacing.l)
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.automatic)
        .id(pane)
    }

    private func takeRequestedModule() {
        guard let module = navigation.menuBarModule else { return }
        pane = .module(module)
        navigation.menuBarModule = nil
    }
}
