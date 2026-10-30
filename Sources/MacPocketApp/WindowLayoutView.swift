import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

/// Tools → Pencere Yerleşimi: keyboard window snapping, gaps and per-action shortcuts.
struct WindowLayoutView: View {
    @ObservedObject private var service = WindowLayoutService.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Pencere Yerleşimi",
                              subtitle: "Öndeki pencereyi kısayollarla ekranın yarısına, çeyreğine, üçte birine veya başka bir ekrana yerleştir.",
                              icon: "rectangle.split.2x1") {
                Toggle("Pencere yerleşimi", isOn: $service.settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(service.settings.enabled ? "Kısayolları kapat" : "Kısayolları aç")
            }
            if !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Pencereleri taşımak için Erişilebilirlik izni gerekir.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            if let message = service.message {
                HStack(alignment: .top) {
                    PocketMessage(message, tone: .warning)
                    Button { service.dismissMessage() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Uyarıyı kapat")
                }
            }
            if !service.refused.isEmpty {
                PocketMessage("Kaydedilemeyen kısayollar: \(service.refused.map(\.title).joined(separator: ", ")). Başka bir uygulama kullanıyor olabilir.",
                              tone: .warning)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    options
                    ForEach(WindowLayoutAction.Group.allCases, id: \.self) { group in
                        shortcuts(group)
                    }
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Seçenekler", icon: "slider.horizontal.3")
            HStack(spacing: PocketSpacing.m) {
                Text("Pencere aralığı")
                Slider(value: $service.settings.gap, in: WindowLayoutSettings.gapRange, step: 2) { Text("Pencere aralığı") }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                Text("\(Int(service.settings.gap)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
            Toggle("Yarım kısayoluna tekrar basınca genişlik değişsin (½ → ⅔ → ⅓)", isOn: $service.settings.cycleOnRepeat)
            Text("Önceki konuma döndürme her pencere için ayrı çalışır ve art arda basıldıkça geriye gider.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private func shortcuts(_ group: WindowLayoutAction.Group) -> some View {
        let conflicts = Set(service.settings.conflicts)
        return VStack(alignment: .leading, spacing: 0) {
            PocketSectionHeader(group.title, icon: group.symbol)
                .padding(.bottom, PocketSpacing.s)
            ForEach(WindowLayoutAction.allCases.filter { $0.group == group }) { action in
                HStack(spacing: PocketSpacing.m) {
                    WindowLayoutPreview(action: action)
                    Text(action.title)
                    if conflicts.contains(action) {
                        PocketStatusBadge(text: "Çakışıyor", systemImage: "exclamationmark.triangle", tone: .warning)
                            .help("Bu kısayol başka bir eylemde de kullanılıyor; yalnız ilki çalışır.")
                    }
                    Spacer(minLength: PocketSpacing.m)
                    if service.settings.shortcut(for: action) != action.defaultShortcut {
                        Button("Varsayılan") { service.settings.shortcuts[action] = nil }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    KeyComboRecorder(combo: Binding(get: { service.settings.shortcut(for: action) },
                                                    set: { service.settings.shortcuts[action] = .some($0) }),
                                     allowsClearing: true,
                                     recording: { service.recording = $0 })
                    Button { tryOut(action) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless)
                        .help("Bu pencerede dene")
                        .accessibilityLabel("\(action.title) yerleşimini bu pencerede dene")
                }
                .padding(.vertical, PocketSpacing.xs + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    /// Applies the layout to MacPocket's own window, the focused one while this page is used.
    private func tryOut(_ action: WindowLayoutAction) {
        trusted = AXIsProcessTrusted()
        service.perform(action)
    }
}

/// A miniature screen with the action's region filled in.
private struct WindowLayoutPreview: View {
    let action: WindowLayoutAction
    @Environment(\.pocketTint) private var tint

    var body: some View {
        let screen = CGRect(x: 0, y: 0, width: 34, height: 22)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            if let region = region(in: screen) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint)
                    .frame(width: region.width, height: region.height)
                    .offset(x: region.minX, y: screen.height - region.maxY)
            } else {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: screen.width, height: screen.height)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .accessibilityHidden(true)
    }

    private func region(in screen: CGRect) -> CGRect? {
        let current = CGRect(x: 0, y: 0, width: 18, height: 12)
        return WindowLayoutGeometry.frame(for: action, in: screen.insetBy(dx: 2, dy: 2), gap: 0.5, current: current)
    }

    private var symbol: String {
        switch action {
        case .nextDisplay: "arrow.right.to.line"
        case .previousDisplay: "arrow.left.to.line"
        default: "arrow.uturn.backward"
        }
    }
}

extension WindowLayoutAction.Group {
    var title: String {
        switch self {
        case .halves: String(localized: "Yarımlar")
        case .quarters: String(localized: "Çeyrekler")
        case .thirds: String(localized: "Üçte birler")
        case .whole: String(localized: "Tüm ekran")
        case .displays: String(localized: "Ekranlar")
        }
    }

    var symbol: String {
        switch self {
        case .halves: "rectangle.split.2x1"
        case .quarters: "rectangle.split.2x2"
        case .thirds: "rectangle.split.3x1"
        case .whole: "macwindow"
        case .displays: "display.2"
        }
    }
}
