import MacPocketShared
import SwiftUI
import WidgetKit

public struct SystemDataEntry: TimelineEntry, Equatable {
    public let date: Date
    public let summary: SystemDataSummary?
    public init(date: Date, summary: SystemDataSummary?) { self.date = date; self.summary = summary }
}

/// Reads the numbers the app wrote after its last scan. The widget itself measures nothing: it is sandboxed
/// and only has read access to that one file.
public struct SystemDataProvider: TimelineProvider {
    public static let refreshInterval: TimeInterval = 30 * 60

    private let load: @Sendable () -> SystemDataSummary?

    public init(load: @escaping @Sendable () -> SystemDataSummary? = {
        SystemDataSummary.realHomeFileURL().flatMap { SystemDataSummary.load(fromFile: $0) }
    }) { self.load = load }

    public func placeholder(in context: Context) -> SystemDataEntry { sampleEntry() }

    public func getSnapshot(in context: Context, completion: @escaping (SystemDataEntry) -> Void) {
        completion(snapshotEntry(isPreview: context.isPreview))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SystemDataEntry>) -> Void) {
        completion(timeline())
    }

    // The context cannot be built outside WidgetKit, so the decisions live here where they can be tested.

    func sampleEntry(now: Date = Date()) -> SystemDataEntry {
        SystemDataEntry(date: now, summary: SystemDataSummary(date: now, systemDataBytes: 41_000_000_000, safeBytes: 6_000_000_000,
                                                              freeBytes: 167_000_000_000, purgeableBytes: 0))
    }

    func snapshotEntry(isPreview: Bool, now: Date = Date()) -> SystemDataEntry {
        isPreview ? sampleEntry(now: now) : SystemDataEntry(date: now, summary: load())
    }

    func timeline(now: Date = Date()) -> Timeline<SystemDataEntry> {
        Timeline(entries: [SystemDataEntry(date: now, summary: load())], policy: .after(now.addingTimeInterval(Self.refreshInterval)))
    }
}

func sizeText(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file, spellsOutZero: false)) }

public struct SystemDataWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: SystemDataEntry
    /// The size to draw. WidgetKit supplies it through the environment; tests pass it explicitly because that
    /// key is read-only.
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    public init(entry: SystemDataEntry, family: WidgetFamily? = nil) { self.entry = entry; familyOverride = family }

    public var body: some View {
        Group {
            if let summary = entry.summary {
                if family == .systemSmall { small(summary) } else { medium(summary) }
            } else {
                empty
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Disk Röntgeni", systemImage: "scope").font(.headline)
            Text("Henüz tarama yok. MacPocket’ta Disk Röntgeni’ni aç ve tara.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func small(_ summary: SystemDataSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Sistem Verisi", systemImage: "scope").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: sizeText(summary.systemDataBytes)).font(.system(.title, design: .rounded).weight(.semibold)).minimumScaleFactor(0.6).lineLimit(1)
            Spacer(minLength: 0)
            safeBar(summary)
            Text("\(sizeText(summary.safeBytes)) güvenle boşaltılabilir").font(.caption2).foregroundStyle(.green).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(sizeText(summary.freeBytes)) boş").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ summary: SystemDataSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disk Röntgeni", systemImage: "scope").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                metric("Sistem Verisi", sizeText(summary.systemDataBytes), .primary)
                metric("Güvenle boşaltılabilir", sizeText(summary.safeBytes), .green)
                metric("Boş alan", sizeText(summary.freeBytes), .blue)
            }
            Spacer(minLength: 0)
            safeBar(summary)
            Text(summary.date, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    /// How much of System Data is Safe, as a bar.
    private func safeBar(_ summary: SystemDataSummary) -> some View {
        let fraction = summary.systemDataBytes > 0 ? min(1, Double(summary.safeBytes) / Double(summary.systemDataBytes)) : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.2))
                Capsule().fill(.green).frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

public struct SystemDataWidget: Widget {
    public static let kind = "MacPocket.SystemData"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SystemDataProvider()) { entry in
            SystemDataWidgetView(entry: entry)
        }
        .configurationDisplayName("Disk Röntgeni")
        .description("Sistem Verisi boyutu, güvenle boşaltılabilir miktar ve boş alan; son taramaya göre.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
