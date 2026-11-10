import AppKit
import MacPocketAIUsage
import MacPocketCore
import SwiftUI
import UsageCore

struct AIUsageProviderIcon: View {
    let provider: AIUsageProvider
    var size: CGFloat = 18
    var body: some View {
        Group {
            if let asset = Self.assets[provider] {
                Image(nsImage: asset).resizable().renderingMode(.template).interpolation(.high)
                    .frame(width: size * (provider == .claude ? 1.25 : 1), height: size * (provider == .claude ? 1.25 : 1))
                    .frame(width: size, height: size)
            } else { Image(systemName: provider.symbol).font(.system(size: size * 0.85, weight: .medium)) }
        }
        .foregroundStyle(provider == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : .primary)
        .accessibilityHidden(true)
    }
    private static let assets: [AIUsageProvider: NSImage] = {
        var images: [AIUsageProvider: NSImage] = [:]
        for (provider, name) in [(AIUsageProvider.claude, "AIProviderClaude"), (.codex, "AIProviderOpenAI")] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) { images[provider] = image }
        }
        return images
    }()
}

enum AIUsagePalette {
    static let secondaryText = Color.primary.opacity(0.8)
    static func color(_ limit: UsageLimit, warning: Double, critical: Double) -> Color {
        if limit.percentUsed >= critical { return .red }
        if limit.percentUsed >= warning { return .orange }
        if limit.id.hasPrefix("weekly_scoped") { return .purple }
        return limit.id == "session" ? .green : .cyan
    }
    static func symbol(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "ellipsis" }
        switch snapshot.status {
        case .ok: return "checkmark.circle"
        case .needsSignIn: return "person.crop.circle.badge.questionmark"
        case .keychainDenied: return "lock.slash"
        case .rateLimited: return "hourglass"
        case .stale: return "clock.badge.exclamationmark"
        case .error: return "exclamationmark.triangle"
        }
    }
    static func shortTitle(_ limit: UsageLimit) -> String {
        if limit.id == "session" { return String(localized: "Quota.short.session", defaultValue: "O") }
        if limit.id == "weekly_all" { return String(localized: "Quota.short.weekly", defaultValue: "H") }
        if limit.id == "monthly" { return String(localized: "Quota.short.monthly", defaultValue: "A") }
        return String(localized: "Quota.short.model", defaultValue: "M")
    }
}

struct AIUsageBar: View {
    let percent: Double
    let color: Color
    var vertical = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: vertical ? .bottom : .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule().fill(colorScheme == .light ? color.mix(with: .black, by: 0.3) : color)
                    .frame(width: vertical ? nil : geometry.size.width * fraction,
                           height: vertical ? geometry.size.height * fraction : nil)
            }
        }
        .frame(width: vertical ? 8 : nil, height: vertical ? nil : 6)
        .accessibilityHidden(true)
    }
    private var fraction: Double { min(100, max(0, percent.isFinite ? percent : 0)) / 100 }
}

struct AIUsageResetLabel: View {
    let date: Date
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if date <= context.date { Text("Sıfırlanma bekleniyor") }
            else { Text("Yenilenme: \(remaining(from: context.date))") }
        }
        .font(.system(size: 11)).foregroundStyle(AIUsagePalette.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .help(String(localized: "Sıfırlanma: \(date.formatted(date: .abbreviated, time: .shortened))"))
    }

    private func remaining(from now: Date) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian); calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = date.timeIntervalSince(now) < 60 ? [.second] : [.day, .hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: now, to: date) ?? date.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
enum AIUsageMenuBarImage {
    static func make(service: AIUsageService, settings: MenuBarModuleSettings, dark: Bool) -> NSImage? {
        let pinned = service.enabledAccounts.filter(\.showInMenuBar)
        guard !pinned.isEmpty, settings.style == .value else { return nil }
        let content = HStack(spacing: 6) {
            ForEach(Array(pinned.prefix(3).enumerated()), id: \.element.id) { index, account in
                if index > 0 { Text("·").foregroundStyle(.secondary) }
                AIUsageProviderIcon(provider: account.provider, size: 13)
                if pinned.filter({ $0.provider == account.provider }).count > 1 {
                    Text(String(account.name.prefix(5))).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                let snapshot = service.snapshot(for: account)
                Text(snapshot?.headlineLimit.map { AIUsageService.percent(service.settings.mode.percent($0.percentUsed)) } ?? "—")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(textColor(snapshot, settings: settings))
                if snapshot != nil && snapshot?.status != .ok { Text("!").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange) }
            }
            if pinned.count > 3 { Text("+\(pinned.count - 3)").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.frame(height: 22).padding(.horizontal, 3).fixedSize()
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }
    private static func textColor(_ snapshot: UsageSnapshot?, settings: MenuBarModuleSettings) -> Color {
        guard settings.colorMode == .thresholds, let used = snapshot?.headlineLimit?.percentUsed else { return .primary }
        return used >= (settings.criticalThreshold ?? 85) ? .red : used >= (settings.warningThreshold ?? 65) ? .orange : .primary
    }
}
