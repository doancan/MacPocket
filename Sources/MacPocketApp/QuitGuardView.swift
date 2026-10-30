import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

/// Tools → Kapatma Koruması: guard ⌘Q and ⌘W against accidental presses.
struct QuitGuardView: View {
    @ObservedObject private var service = QuitGuardService.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Kapatma Koruması",
                              subtitle: "⌘Q ve ⌘W’ye yanlışlıkla basınca uygulama ya da pencere kapanmasın; basılı tut veya iki kez bas.",
                              icon: "hand.raised.fill") {
                if service.tapActive {
                    PocketStatusBadge(text: "Etkin", systemImage: "checkmark.circle.fill", tone: .success)
                } else if service.settings.isActive {
                    PocketStatusBadge(text: "İzin bekliyor", systemImage: "lock", tone: .warning)
                } else {
                    PocketStatusBadge(text: "Kapalı", systemImage: "circle", tone: .neutral)
                }
            }
            if !trusted && service.settings.isActive {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Kısayolları yakalamak için Erişilebilirlik izni gerekir. İzin verdikten sonra MacPocket’e dönmen yeterli.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    shortcutCard(.quit, title: "Uygulamadan çık", mode: $service.settings.quitMode)
                    shortcutCard(.closeWindow, title: "Pencereyi kapat", mode: $service.settings.closeMode)
                    timing
                    scope
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
            service.configure()
        }
    }

    private func shortcutCard(_ shortcut: GuardedShortcut, title: LocalizedStringKey, mode: Binding<QuitGuardMode>) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                Text(verbatim: shortcut.symbol)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .padding(.horizontal, PocketSpacing.s).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title).font(.title3.weight(.semibold))
            }
            GlassTabBar(tabs: QuitGuardMode.allCases.map { GlassTab(id: $0, title: $0.title, symbol: $0.symbol) }, selection: mode)
                .accessibilityLabel(Text(title))
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Zamanlama", icon: "timer")
            slider("Basılı tutma süresi", value: $service.settings.holdDuration, range: QuitGuardSettings.holdRange)
            slider("İki basış arasındaki en uzun süre", value: $service.settings.doublePressInterval, range: QuitGuardSettings.doublePressRange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Text(title).frame(width: 240, alignment: .leading)
            Slider(value: value, in: range, step: 0.05) { Text(title) }.labelsHidden().frame(maxWidth: 260)
            Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(2)).locale(pocketLocale))) sn")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
        }
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Uygulamalar", icon: "app.badge")
            Picker("Koruma kapsamı", selection: $service.settings.scope) {
                Text("Tüm uygulamalar, listedekiler hariç").tag(QuitGuardSettings.Scope.allExcept)
                Text("Yalnız listedeki uygulamalar").tag(QuitGuardSettings.Scope.only)
            }
            .pickerStyle(.radioGroup)
            ForEach(service.settings.apps, id: \.self) { bundleID in
                HStack(spacing: PocketSpacing.s) {
                    PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), size: 20)
                    Text(Self.name(of: bundleID))
                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { service.settings.apps.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(Self.name(of: bundleID)) uygulamasını listeden çıkar")
                }
            }
            Button { addApplications() } label: { Label("Uygulama ekle…", systemImage: "plus") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private static func name(of bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !service.settings.apps.contains($0) }
        service.settings.apps.append(contentsOf: ids)
    }
}

extension QuitGuardMode {
    var title: String {
        switch self {
        case .off: String(localized: "Kapalı")
        case .hold: String(localized: "Basılı tut")
        case .doublePress: String(localized: "İki kez bas")
        }
    }

    var symbol: String {
        switch self {
        case .off: "circle.slash"
        case .hold: "hand.tap"
        case .doublePress: "repeat"
        }
    }
}
