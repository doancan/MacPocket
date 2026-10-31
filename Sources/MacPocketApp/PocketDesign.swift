import AppKit
import Charts
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tokens

/// One spacing scale for every screen; values follow the macOS 8-pt rhythm. The larger steps shrink
/// with the "compact" card density (Settings → Appearance); the window content is rebuilt when it changes.
enum PocketSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static var m: CGFloat { 12 * PocketDensity.current.scale }
    static var l: CGFloat { 16 * PocketDensity.current.scale }
    static var xl: CGFloat { 24 * PocketDensity.current.scale }
    static var xxl: CGFloat { 32 * PocketDensity.current.scale }
    /// Outer padding of a detail page.
    static var page: CGFloat { 24 * PocketDensity.current.scale }
}

enum PocketRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
}

/// Semantic tones shared by badges, banners and metric colors.
enum PocketTone {
    case neutral, accent, success, warning, critical

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .accent: PocketTheme.accent
        case .success: PocketTheme.disk
        case .warning: .orange
        case .critical: .red
        }
    }

    var symbol: String {
        switch self {
        case .neutral, .accent: "info.circle"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .critical: "xmark.octagon"
        }
    }
}

// MARK: - Surfaces

private struct PocketCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            // The shadow belongs to the background shape only: shadowing the whole card made every
            // text run and icon cast a shadow and forced an offscreen render pass per card.
            .background {
                shape.fill(PocketTheme.panel.shadow(.drop(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06),
                                                          radius: colorScheme == .dark ? 6 : 10, y: colorScheme == .dark ? 2 : 3)))
            }
            .overlay {
                // Dark mode: a faint top highlight reads as elevation; light mode relies on the shadow.
                shape.strokeBorder(LinearGradient(colors: colorScheme == .dark ? [.white.opacity(0.10), .white.opacity(0.04)]
                                                                               : [.black.opacity(0.06), .black.opacity(0.05)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }
}

extension View {
    /// The standard grouped surface: control background, hairline border, continuous corners.
    func pocketCard(padding: CGFloat = PocketSpacing.l, radius: CGFloat = PocketRadius.large) -> some View {
        modifier(PocketCardModifier(padding: padding, radius: radius))
    }

    /// Standard detail-page frame: fills the split view column and pins content to the top leading edge.
    func pocketPage() -> some View {
        padding(PocketSpacing.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Headings

struct PocketPageHeading<Accessory: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.pocketTint) private var tint

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            PocketIconTile(symbol: icon, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(title).font(.system(.title, design: .default, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PocketSpacing.m)
            accessory()
        }
    }
}

extension PocketPageHeading where Accessory == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

struct PocketSectionHeader<Trailing: View>: View {
    let title: Text
    var icon: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: LocalizedStringKey, icon: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Text(title); self.icon = icon; self.trailing = trailing
    }

    /// Already-localized or user data text, shown verbatim.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Text(title); self.icon = icon; self.trailing = trailing
    }

    @Environment(\.pocketTint) private var tint

    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            if let icon {
                Label { title } icon: { Image(systemName: icon).foregroundStyle(tint) }
            } else {
                title
            }
            Spacer(minLength: PocketSpacing.s)
            trailing().font(.callout).foregroundStyle(.secondary)
        }
        .font(.title3.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
    }
}

extension PocketSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, icon: String? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: String? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }
}

// MARK: - Feedback

/// Inline status message. Errors stay selectable so users can copy them into a report.
struct PocketMessage: View {
    let message: Text
    let tone: PocketTone

    init(_ message: LocalizedStringKey, error: Bool = false) {
        self.message = Text(message)
        tone = error ? .warning : .success
    }

    init(_ message: LocalizedStringKey, tone: PocketTone) {
        self.message = Text(message); self.tone = tone
    }

    /// Already-localized text (for example an error's `localizedDescription`), shown verbatim. Generic like
    /// `Text`'s own overload: a concrete `String` overload would win over the key for literals followed by
    /// further arguments (`PocketMessage("…", tone: .warning)`), leaving them unlocalized.
    @_disfavoredOverload
    init<S: StringProtocol>(_ message: S, error: Bool = false) {
        self.message = Text(message)
        tone = error ? .warning : .success
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ message: S, tone: PocketTone) {
        self.message = Text(message); self.tone = tone
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.s) {
            Image(systemName: tone.symbol).foregroundStyle(tone.color)
                .accessibilityHidden(true)
            message.foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(PocketSpacing.m)
        .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                .strokeBorder(tone.color.opacity(0.25), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PocketStatusBadge: View {
    let text: Text
    var systemImage: String?
    var tone: PocketTone = .neutral

    init(text: LocalizedStringKey, systemImage: String? = nil, tone: PocketTone = .neutral) {
        self.text = Text(text); self.systemImage = systemImage; self.tone = tone
    }

    /// Already-localized or user data text, shown verbatim.
    @_disfavoredOverload
    init<S: StringProtocol>(text: S, systemImage: String? = nil, tone: PocketTone = .neutral) {
        self.text = Text(text); self.systemImage = systemImage; self.tone = tone
    }

    var body: some View {
        Group {
            if let systemImage {
                Label { text } icon: { Image(systemName: systemImage) }
            } else {
                text
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tone.color)
        .padding(.horizontal, PocketSpacing.s)
        .padding(.vertical, PocketSpacing.xxs + 1)
        .background(tone.color.opacity(0.12), in: Capsule())
    }
}

/// Progress row shown while a long operation runs.
struct PocketProgressRow: View {
    let message: Text

    init(message: LocalizedStringKey) { self.message = Text(message) }

    /// Already-localized text, shown verbatim.
    @_disfavoredOverload
    init<S: StringProtocol>(message: S) { self.message = Text(message) }

    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            ProgressView().controlSize(.small)
            message.font(.callout).foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metrics

/// Compact KPI tile with an optional live sparkline.
/// Text parameters are localization keys; pass dynamic values by interpolation (`"\(value)"`).
struct PocketMetricTile: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let detail: LocalizedStringKey
    var icon: String
    var color: Color
    var history: [Double] = []
    /// Upper bound for the sparkline's y-axis; nil scales to the data.
    var historyCeiling: Double? = 100

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold)).foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.14), in: Circle())
                Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            // Space is always reserved so tiles with and without a trend line align in a row.
            Group {
                if history.count > 1 {
                    PocketSparkline(values: history, color: color, ceiling: historyCeiling)
                } else {
                    Color.clear
                }
            }
            .frame(height: 26)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard(padding: PocketSpacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value) + Text(verbatim: ". ") + Text(detail))
    }
}

struct PocketSparkline: View {
    let values: [Double]
    let color: Color
    var ceiling: Double? = 100

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value(Text("Örnek"), index), y: .value(Text("Değer"), value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value(Text("Örnek"), index), y: .value(Text("Değer"), value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(ceiling ?? max(1, values.max() ?? 1)))
        .accessibilityHidden(true)
    }
}

/// Circular capacity ring. The value is clamped to 0…1.
struct PocketRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // No implicit animation: live samples arrive every 1–2 s, and animating each one
                // keeps the render loop busy for a large share of the interval.
        }
        .accessibilityHidden(true)
    }
}

/// Ring with a centered value and a caption underneath.
/// Text parameters are localization keys; pass dynamic values by interpolation (`"\(value)"`).
struct PocketRingMetric: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let fraction: Double?
    let color: Color
    var size: CGFloat = 76

    var body: some View {
        VStack(spacing: PocketSpacing.s) {
            ZStack {
                PocketRing(fraction: fraction ?? 0, color: color)
                Text(value).font(.headline).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(PocketSpacing.s)
            }
            .frame(width: size, height: size)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

// MARK: - Icons

/// `NSWorkspace.icon(forFile:)` hits LaunchServices and decodes an image on every call.
/// Table rows re-render often, so icons are cached by path.
@MainActor
enum PocketIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    /// Icons are rasterised once at the size they are shown (32, 64 or 128 pt buckets, @2x). Keeping the
    /// workspace NSImage itself retained every representation up to 1024 px and cost ~300 MB for 119 apps.
    static func icon(for url: URL, pointSize: CGFloat = 32) -> NSImage {
        let bucket: CGFloat = pointSize <= 32 ? 32 : pointSize <= 64 ? 64 : 128
        let key = "\(url.path)#\(Int(bucket))" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = rasterize(NSWorkspace.shared.icon(forFile: url.path), points: bucket)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Type icon keyed by extension, so scanning thousands of files keeps a handful of cache entries.
    /// Folders and packages (which may carry custom icons) still resolve by path.
    static func typeIcon(for url: URL, isDirectory: Bool) -> NSImage {
        if isDirectory { return icon(for: url) }
        let ext = url.pathExtension.lowercased()
        let key = "type:\(ext)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let type = UTType(filenameExtension: ext) ?? .data
        let image = rasterize(NSWorkspace.shared.icon(for: type), points: 32)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func rasterize(_ source: NSImage, points: CGFloat) -> NSImage {
        let pixels = Int(points * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

struct PocketAppIcon: View {
    let url: URL?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url {
                Image(nsImage: PocketIconCache.icon(for: url, pointSize: size)).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Formatting

/// Formatters follow the language the app is running in (Settings → General → Language),
/// not the system region, so numbers and units match the surrounding copy.
let pocketLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "tr")

@MainActor private let pocketByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowsNonnumericFormatting = false
    return formatter
}()

@MainActor
func pocketBytes(_ value: UInt64) -> String {
    pocketByteFormatter.string(fromByteCount: Int64(clamping: value))
}

@MainActor
func pocketBytes(_ value: Int64) -> String {
    pocketByteFormatter.string(fromByteCount: max(0, value))
}

func pocketPercent(_ value: Double, decimals: Bool = false) -> String {
    (value / 100).formatted(.percent.precision(.fractionLength(decimals ? 1 : 0)).locale(pocketLocale))
}

/// A process's per-core CPU sample in the scale chosen in Settings → Monitoring.
func pocketProcessCPU(_ perCorePercent: Double) -> String {
    let scale = ProcessCPUScale.load(from: .standard)
    return pocketPercent(scale.value(perCorePercent, logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount), decimals: true)
}

/// Human description of `ProcessInfo.ThermalState` names produced by the core.
func pocketThermalTitle(_ state: String?) -> String {
    switch state {
    case "nominal": String(localized: "Normal")
    case "fair": String(localized: "Hafif yüksek")
    case "serious": String(localized: "Yüksek")
    case "critical": String(localized: "Kritik")
    case nil: "—"
    default: String(localized: "Bilinmiyor")
    }
}

func pocketThermalTone(_ state: String?) -> PocketTone {
    switch state {
    case "nominal": .success
    case "fair": .warning
    case "serious", "critical": .critical
    default: .neutral
    }
}

func pocketPowerSourceTitle(_ source: String?) -> String {
    switch source {
    case "AC Power": String(localized: "Priz")
    case "Battery Power": String(localized: "Pil")
    case "UPS Power": "UPS"
    case nil, "unknown": String(localized: "Bilinmiyor")
    case let value?: value
    }
}

func pocketDuration(_ seconds: Double) -> String {
    let minutes = Int(max(0, seconds) / 60)
    let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
    if days > 0 { return hours > 0 ? String(localized: "\(days) gün \(hours) sa") : String(localized: "\(days) gün") }
    if hours > 0 { return rest > 0 ? String(localized: "\(hours) sa \(rest) dk") : String(localized: "\(hours) sa") }
    return String(localized: "\(rest) dk")
}

/// Core reports BSD process states in English identifiers.
func pocketProcessStateTitle(_ state: String) -> String {
    switch state {
    case "running": String(localized: "Çalışıyor")
    case "sleeping": String(localized: "Bekliyor")
    case "stopped": String(localized: "Durduruldu")
    case "starting": String(localized: "Başlatılıyor")
    case "zombie": String(localized: "Zombi")
    default: String(localized: "Bilinmiyor")
    }
}

// Note: never apply `.clipShape` to a container holding a Table/List/NSScrollView. It forces the whole
// scrolled content into an offscreen mask (measured: +230 MB GPU memory on the Applications table).
// Use a stroked overlay for the rounded frame instead.

// MARK: - Controls

/// Search field used on every page: fixed 30 pt height, magnifier, clear button, accent focus ring.
/// Pass the page's FocusState binding to keep ⌘F (pocketFind) focusing working.
struct PocketSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var focus: FocusState<Bool>.Binding?
    @FocusState private var ownFocus: Bool
    @State private var hovering = false

    init(_ prompt: LocalizedStringKey, text: Binding<String>, focus: FocusState<Bool>.Binding? = nil) {
        self.prompt = prompt; _text = text; self.focus = focus
    }

    private var isFocused: Bool { focus?.wrappedValue ?? ownFocus }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            field
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Aramayı temizle")
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .modifier(PocketSearchFieldSurface(isFocused: isFocused, hovering: hovering))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    @ViewBuilder private var field: some View {
        let textField = TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.body)
            .onExitCommand { text = "" }
        if let focus { textField.focused(focus) } else { textField.focused($ownFocus) }
    }
}

/// macOS 26+: an interactive glass capsule, tinted with the accent color while focused.
/// Earlier systems: a panel fill with a hairline that turns into an accent focus ring.
private struct PocketSearchFieldSurface: ViewModifier {
    let isFocused: Bool
    let hovering: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .contentShape(Capsule())
                .glassEffect(isFocused ? .regular.tint(Color.accentColor.opacity(0.18)).interactive() : .regular.interactive(),
                             in: .capsule)
        } else {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            content
                .background(shape.fill(PocketTheme.panel))
                .overlay {
                    shape.strokeBorder(isFocused ? Color.accentColor.opacity(0.85) : (hovering ? PocketTheme.line.opacity(2) : PocketTheme.line.opacity(1.4)),
                                       lineWidth: isFocused ? 1.5 : 0.75)
                }
                .contentShape(shape)
        }
    }
}

/// Primary and secondary buttons, applied app-wide as the default button style.
/// - macOS 26+: the system Liquid Glass styles (`.glassProminent` for the primary action, `.glass`
///   otherwise), which bring their own press, hover and shimmer feedback.
/// - Earlier systems: a filled accent / surface + hairline look with one height per control size.
struct PocketButtonStyle: PrimitiveButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            switch kind {
            case .primary: Button(configuration).buttonStyle(.glassProminent)
            case .secondary: Button(configuration).buttonStyle(.glass)
            }
        } else {
            Button(configuration).buttonStyle(PocketLegacyButtonStyle(kind: kind))
        }
    }
}

private struct PocketLegacyButtonStyle: ButtonStyle {
    let kind: PocketButtonStyle.Kind

    func makeBody(configuration: Configuration) -> some View {
        PocketButtonBody(configuration: configuration, kind: kind)
    }
}

private struct PocketButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: PocketButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var metrics: (height: CGFloat, padding: CGFloat, font: CGFloat) {
        switch controlSize {
        case .mini, .small: (24, 10, 12)
        case .large, .extraLarge: (34, 16, 14)
        default: (28, 13, 13)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let primary = kind == .primary
        configuration.label
            .font(.system(size: metrics.font, weight: primary ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, metrics.padding)
            .frame(minHeight: metrics.height)
            .background {
                if primary {
                    shape.fill(Color.accentColor.gradient.shadow(.drop(color: .black.opacity(0.15), radius: 1.5, y: 1)))
                } else {
                    shape.fill(PocketTheme.panel.shadow(.drop(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 1, y: 0.5)))
                }
            }
            .overlay {
                shape.fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.05 : 0)))
                shape.strokeBorder(primary ? Color.white.opacity(0.18) : PocketTheme.line.opacity(1.6), lineWidth: 0.75)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension PrimitiveButtonStyle where Self == PocketButtonStyle {
    static var pocketPrimary: PocketButtonStyle { PocketButtonStyle(kind: .primary) }
    static var pocketSecondary: PocketButtonStyle { PocketButtonStyle(kind: .secondary) }
}
