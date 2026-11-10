import AppKit
import MacPocketAIUsage
import MacPocketCore
import SwiftUI
import UsageCore

struct AIUsageDetailView: View {
    @ObservedObject var service = AIUsageService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(service.settings.mode.localizedTitle).font(.caption).foregroundStyle(AIUsagePalette.secondaryText)
                Spacer()
                Button { Task { await service.refresh(manual: true) } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .labelStyle(.iconOnly).disabled(!service.active || !service.refreshing.isEmpty)
                Button { AIUsageIntegration.shared.openSettingsWindow?() } label: { Label("Hesaplar", systemImage: "slider.horizontal.3") }
                    .labelStyle(.iconOnly)
            }.controlSize(.small).buttonStyle(.borderless)
            if service.settings.accounts.isEmpty {
                AIUsageEmptyView { AIUsageIntegration.shared.openSettingsWindow?() }
            } else if service.enabledAccounts.isEmpty {
                Text("Tüm hesaplar duraklatıldı. Takibi sürdürmek için Hesaplar’dan bir hesabı etkinleştir.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(service.enabledAccounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { Divider() }
                            AIUsageAccountQuotaView(account: account, snapshot: service.snapshot(for: account), settings: service.settings,
                                refreshing: service.refreshing.contains(account.id), dense: true)
                        }
                    }
                }.frame(maxHeight: 440)
            }
            if !service.active { Button("AI kota takibini etkinleştir") { AIUsageIntegration.shared.enableMenuBar() } }
            if let error = service.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("Yüzen panel").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Yüzen kota panelini göster", isOn: Binding(get: { service.settings.floatingPanel }, set: { value in
                    var settings = service.settings; settings.floatingPanel = value; service.setSettings(settings)
                })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        }
    }
}

struct AIUsageDashboardView: View {
    @ObservedObject var service: AIUsageService
    let onAdd: () -> Void
    var body: some View {
        if service.settings.accounts.isEmpty { AIUsageEmptyView(onAdd: onAdd).frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if service.enabledAccounts.isEmpty {
            ContentUnavailableView {
                Label("Hesaplar duraklatıldı", systemImage: "pause.circle")
            } description: { Text("Tüm hesaplar duraklatıldı. Takibi sürdürmek için Hesaplar’dan bir hesabı etkinleştir.") }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.enabledAccounts) { account in
                        AIUsageAccountQuotaView(account: account, snapshot: service.snapshot(for: account), settings: service.settings,
                            refreshing: service.refreshing.contains(account.id))
                            .padding(14).background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)) }
                    }
                }.padding(.horizontal, 22).padding(.vertical, 14)
            }
        }
    }
}

struct AIUsageEmptyView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                ForEach(AIUsageProvider.allCases) { AIUsageProviderIcon(provider: $0, size: 26) }
            }.padding(.bottom, 4)
            Text("Kotanı tek bakışta gör.").font(.title3.weight(.semibold))
            Text("Claude, Codex ve Grok hesaplarını ekle; oturum ve haftalık limitlerini birlikte izle.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("İlk Hesabı Ekle", systemImage: "plus", action: onAdd).buttonStyle(.borderedProminent)
        }.padding(24).frame(maxWidth: 400)
    }
}

struct AIUsageAccountQuotaView: View {
    let account: AIUsageAccount
    let snapshot: UsageSnapshot?
    let settings: AIUsageSettings
    var refreshing = false
    var dense = false

    private var warning: (title: LocalizedStringKey, symbol: String, color: Color)? {
        guard snapshot?.status == .ok, let used = snapshot?.headlineLimit?.percentUsed, used.isFinite else { return nil }
        if used >= 100 { return ("Kota doldu", "exclamationmark.circle.fill", .red) }
        if used >= settings.critical { return ("Az kota kaldı", "exclamationmark.circle.fill", .red) }
        if used >= settings.warning { return ("Kota azalıyor", "exclamationmark.triangle.fill", .orange) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                AIUsageProviderIcon(provider: account.provider, size: dense ? 20 : 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name).font(.system(size: dense ? 13 : 15, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle).help(account.name)
                    HStack(spacing: 5) {
                        Text(account.provider.localizedTitle)
                        if let date = snapshot?.fetchedAt {
                            Text("·").accessibilityHidden(true)
                            TimelineView(.periodic(from: .now, by: 30)) { _ in Text(date, style: .relative) }
                                .help(String(localized: "Son veri: \(date.formatted(date: .abbreviated, time: .shortened))"))
                        }
                    }.font(.system(size: 11)).foregroundStyle(AIUsagePalette.secondaryText)
                }.layoutPriority(1)
                Spacer(minLength: 4)
                if refreshing {
                    ProgressView().controlSize(.small).accessibilityLabel("Kotalar yenileniyor")
                } else if let warning {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            Image(systemName: warning.symbol).foregroundStyle(warning.color).accessibilityHidden(true)
                            Text(warning.title).foregroundStyle(.primary)
                        }.fixedSize()
                        Image(systemName: warning.symbol).foregroundStyle(warning.color).accessibilityLabel(Text(warning.title))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .help(Text(warning.title))
                }
            }
            if let snapshot, !snapshot.limits.isEmpty {
                let shared = snapshot.limits.filter { !$0.id.hasPrefix("weekly_scoped") }
                let scoped = snapshot.limits.filter { $0.id.hasPrefix("weekly_scoped") }
                LazyVGrid(columns: shared.count == 1 ? [GridItem(.flexible())] :
                          [GridItem(.flexible(), spacing: dense ? 20 : 28, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: dense ? 14 : 18) {
                    ForEach(shared) { limit in lane(limit) }
                }
                ForEach(scoped) { limit in lane(limit) }
            }
            if snapshot?.status != .ok || snapshot?.limits.isEmpty == true {
                Label(AIUsageText.status(snapshot), systemImage: AIUsagePalette.symbol(snapshot))
                    .font(.system(size: 12)).foregroundStyle(AIUsagePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lane(_ limit: UsageLimit) -> some View {
        let tint = AIUsagePalette.color(limit, warning: settings.warning, critical: settings.critical)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AIUsageText.limitTitle(limit)).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AIUsagePalette.secondaryText).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(AIUsageService.percent(settings.mode.percent(limit.percentUsed)))
                    .font(.system(size: dense ? 23 : 27, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
            AIUsageBar(percent: settings.mode.percent(limit.percentUsed), color: tint)
                .opacity(snapshot?.status == .ok ? 1 : 0.45)
            if let reset = limit.resetsAt { AIUsageResetLabel(date: reset) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(AIUsageText.limitTitle(limit)): \(AIUsageService.percent(settings.mode.percent(limit.percentUsed))) · \(settings.mode.localizedTitle)"))
        .accessibilityValue(limit.resetsAt.map { String(localized: "Sıfırlanma: \($0.formatted(date: .abbreviated, time: .shortened))") } ?? "")
    }
}

struct AIUsageFloatingView: View {
    @ObservedObject var service: AIUsageService
    var body: some View {
        Group {
            if service.settings.floatingHorizontal {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) { accountItems }
                    }
                    controls(horizontal: true)
                }.padding(10)
            } else {
                VStack(spacing: 9) {
                    controls(horizontal: false)
                    ScrollView(.vertical, showsIndicators: false) { VStack(spacing: 12) { accountItems } }
                }.padding(9)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5) }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    @ViewBuilder private var accountItems: some View {
        if service.enabledAccounts.isEmpty {
            Button { AIUsageIntegration.shared.openSettingsWindow?() } label: { Label("Hesap Ekle", systemImage: "plus") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).frame(width: 50, height: 50)
        } else {
            ForEach(Array(service.enabledAccounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle().fill(.primary.opacity(0.12))
                        .frame(width: service.settings.floatingHorizontal ? 1 : 48, height: service.settings.floatingHorizontal ? 40 : 1)
                }
                AIUsageStripAccount(account: account, snapshot: service.snapshot(for: account), settings: service.settings)
            }
        }
    }
    private func controls(horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            AIUsagePanelDragHandle().frame(width: horizontal ? 16 : 10, height: 14)
                .help("Paneli sürükle")
            Button { AIUsageIntegration.shared.openSettingsWindow?() } label: { Label("Hesaplar", systemImage: "slider.horizontal.3") }
            Button {
                var settings = service.settings; settings.floatingHorizontal.toggle(); service.setSettings(settings)
            } label: { Label("Yönü Değiştir", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
            Button {
                var settings = service.settings; settings.floatingPanel = false; service.setSettings(settings)
            } label: { Label("Yüzen Paneli Kapat", systemImage: "xmark") }
        }
        .font(.system(size: 10)).labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
    }
}

private struct AIUsageStripAccount: View {
    let account: AIUsageAccount
    let snapshot: UsageSnapshot?
    let settings: AIUsageSettings
    private var limits: [UsageLimit] {
        let primary = [snapshot?.sessionLimit, snapshot?.weeklyLimit].compactMap { $0 }
        return primary.isEmpty ? snapshot?.headlineLimit.map { [$0] } ?? [] : primary
    }
    var body: some View {
        Button { AIUsageIntegration.shared.openSettingsWindow?() } label: {
            Group {
                if settings.floatingHorizontal { horizontal }
                else { vertical }
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(helpText)
    }
    private var identity: some View {
        HStack(spacing: 5) {
            AIUsageProviderIcon(provider: account.provider, size: 13)
            Text(account.name).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.tail)
        }
    }
    private var vertical: some View {
        VStack(spacing: 6) {
            identity
            if limits.isEmpty { missing.frame(height: 72) }
            else {
                HStack(spacing: 8) {
                    ForEach(limits) { limit in
                        VStack(spacing: 4) {
                            percent(limit).font(.system(size: 10, weight: .semibold).monospacedDigit())
                            AIUsageBar(percent: settings.mode.percent(limit.percentUsed), color: tint(limit), vertical: true).frame(height: 49)
                            Text(AIUsagePalette.shortTitle(limit)).font(.system(size: 9)).foregroundStyle(.secondary)
                        }.frame(width: 29)
                    }
                }
            }
            if snapshot?.status != .ok && !limits.isEmpty { Image(systemName: AIUsagePalette.symbol(snapshot)).font(.system(size: 9)).foregroundStyle(.orange) }
        }.frame(width: 76)
    }
    private var horizontal: some View {
        VStack(alignment: .leading, spacing: 7) {
            identity
            if limits.isEmpty { missing.frame(maxWidth: .infinity, alignment: .leading) }
            else {
                ForEach(limits) { limit in
                    HStack(spacing: 5) {
                        Text(AIUsagePalette.shortTitle(limit)).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 11)
                        AIUsageBar(percent: settings.mode.percent(limit.percentUsed), color: tint(limit))
                        percent(limit).font(.system(size: 10, weight: .semibold).monospacedDigit()).frame(width: 31, alignment: .trailing)
                    }
                }
            }
        }.frame(width: 146)
    }
    private var missing: some View {
        VStack(spacing: 5) {
            Image(systemName: AIUsagePalette.symbol(snapshot)).font(.system(size: 15)).foregroundStyle(.secondary)
            Text("—").font(.system(size: 12).monospacedDigit())
        }
    }
    private func percent(_ limit: UsageLimit) -> Text { Text(AIUsageService.percent(settings.mode.percent(limit.percentUsed))) }
    private func tint(_ limit: UsageLimit) -> Color {
        AIUsagePalette.color(limit, warning: settings.warning, critical: settings.critical).opacity(snapshot?.status == .ok ? 1 : 0.5)
    }
    private var helpText: String {
        var lines = [account.name + " · " + account.provider.localizedTitle, settings.mode.localizedTitle]
        for limit in limits {
            var line = AIUsageText.limitTitle(limit) + ": " + AIUsageService.percent(settings.mode.percent(limit.percentUsed))
            if let date = limit.resetsAt { line += " · " + String(localized: "Sıfırlanma: \(date.formatted(date: .abbreviated, time: .shortened))") }
            lines.append(line)
        }
        if let date = snapshot?.fetchedAt { lines.append(String(localized: "Son veri: \(date.formatted(date: .abbreviated, time: .shortened))")) }
        if snapshot?.status != .ok { lines.append(AIUsageText.status(snapshot)) }
        return lines.joined(separator: "\n")
    }
}

private struct AIUsagePanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Handle(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class Handle: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
            for y in stride(from: CGFloat(3), to: bounds.height - 2, by: 4) {
                NSBezierPath(roundedRect: CGRect(x: bounds.midX - 2, y: y, width: 4, height: 2), xRadius: 1, yRadius: 1).fill()
            }
        }
    }
}
