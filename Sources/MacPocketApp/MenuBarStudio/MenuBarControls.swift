import AppKit
import MacPocketCore
import SwiftUI

// MARK: - Card and rows

/// A titled settings group. Titles are headings for VoiceOver; the footer explains in one or two sentences.
struct StudioCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content
    @Environment(\.pocketTint) private var tint

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(tint) }
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
            if let footer {
                Text(footer).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

/// A label with an optional explanation on the leading side and its control on the trailing side.
struct StudioRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(title)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: PocketSpacing.m)
            control
        }
        .accessibilityElement(children: .combine)
    }
}

/// A switch row for one on/off option.
struct StudioToggle: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.m) {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(title)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: PocketSpacing.s)
            Toggle(title, isOn: $isOn).pocketSwitch().labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Segmented choice with a trailing title row; the picker keeps the system's glass segmented look.
struct StudioSegmented<ID: Hashable & Identifiable>: View where ID: CaseIterable {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var selection: ID
    var options: [ID] = Array(ID.allCases)
    let label: (ID) -> Text

    var body: some View {
        StudioRow(title: title, detail: detail) {
            Picker(title, selection: $selection) {
                ForEach(options) { label($0).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}

// MARK: - Style gallery

/// One alternative in a style gallery: a real rendering of the item with that choice applied.
struct StyleChoice<ID: Hashable>: Identifiable {
    let id: ID
    let title: Text
    let image: NSImage
    var detail: Text?
}

/// A grid of tiles, each showing the actual menu bar rendering of a choice on a miniature menu bar.
struct StyleGallery<ID: Hashable>: View {
    let choices: [StyleChoice<ID>]
    @Binding var selection: ID
    let surface: MenuBarSurface
    var minimumWidth: CGFloat = 132

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth, maximum: 200), spacing: PocketSpacing.m)],
                  alignment: .leading, spacing: PocketSpacing.m) {
            ForEach(choices) { choice in
                StyleTile(choice: choice, selected: choice.id == selection, surface: surface) {
                    withAnimation(.snappy(duration: 0.2)) { selection = choice.id }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct StyleTile<ID: Hashable>: View {
    let choice: StyleChoice<ID>
    let selected: Bool
    let surface: MenuBarSurface
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: PocketSpacing.s) {
                ZStack {
                    LinearGradient(colors: surface.wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing)
                    surface.barFill
                    Image(nsImage: surface.flatten(choice.image))
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(height: choice.image.size.height * 1.35)
                        .padding(.horizontal, PocketSpacing.s)
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous).strokeBorder(PocketTheme.line) }
                VStack(spacing: 1) {
                    choice.title.font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                    if let detail = choice.detail { detail.font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .foregroundStyle(.primary)
            }
            .padding(PocketSpacing.s)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.06 : 0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : PocketTheme.line, lineWidth: selected ? 2 : 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Color

/// The accent color choices of an item: automatic (follows the menu bar) and eight fixed colors.
struct AccentSwatches: View {
    @Binding var selection: MenuBarAccent

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            ForEach(MenuBarAccent.allCases) { accent in
                let selected = selection == accent
                Button { selection = accent } label: {
                    ZStack {
                        if let color = accent.swatch {
                            Circle().fill(color.gradient)
                        } else {
                            Circle().fill(Color.primary.opacity(0.10))
                            Image(systemName: "circle.lefthalf.filled").font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.75) }
                    .padding(3)
                    .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0) }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text(accent.title))
                .accessibilityLabel(Text(accent.title))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Thresholds

/// Warning and critical limits as two sliders under a bar that shows the calm, warning and critical zones and
/// where the current reading falls. The settings keep the two limits ordered (see
/// `MenuBarModuleSettings.setWarningThreshold`).
struct ThresholdEditor: View {
    @Binding var settings: MenuBarModuleSettings
    let currentValue: Double?
    private static let dotWidth: CGFloat = 10
    private static let titleWidth: CGFloat = 56
    private static let valueWidth: CGFloat = 76

    var body: some View {
        if let unit = settings.value.thresholdUnit, let limits = settings.thresholds {
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                // Lined up with the sliders' tracks: dot, title and value columns are skipped on both sides.
                ThresholdZones(unit: unit, limits: limits, lowerIsWorse: settings.value.lowerIsWorse, current: currentValue)
                    .padding(.leading, Self.dotWidth + Self.titleWidth + PocketSpacing.s * 2)
                    .padding(.trailing, Self.valueWidth + PocketSpacing.s)
                slider(String(localized: "Uyarı"), color: .orange, unit: unit, value: limits.warning) { settings.setWarningThreshold($0) }
                slider(String(localized: "Kritik"), color: .red, unit: unit, value: limits.critical) { settings.setCriticalThreshold($0) }
                HStack(alignment: .firstTextBaseline) {
                    Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: PocketSpacing.s)
                    if settings.warningThreshold != nil || settings.criticalThreshold != nil {
                        Button("Varsayılana Dön") { settings.warningThreshold = nil; settings.criticalThreshold = nil }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func slider(_ title: String, color: Color, unit: MenuBarThresholdUnit, value: Double,
                        set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Circle().fill(color).frame(width: Self.dotWidth, height: Self.dotWidth).accessibilityHidden(true)
            Text(verbatim: title).frame(width: Self.titleWidth, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { set(($0 / unit.step).rounded() * unit.step) }), in: unit.range, step: unit.step)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityValue(Text(verbatim: format(value, unit)))
            Text(verbatim: format(value, unit)).monospacedDigit().frame(width: Self.valueWidth, alignment: .trailing)
        }
    }

    private func format(_ value: Double, _ unit: MenuBarThresholdUnit) -> String {
        switch unit {
        case .percent: MenuBarFormatter.percentText(MenuBarFormatter.number(value, fractionDigits: 0))
        default: MenuBarFormatter.number(value, fractionDigits: 0) + " " + unit.symbol
        }
    }

    private var explanation: String {
        let measured: String = switch settings.value {
        case .memoryFreeBytes, .diskFreeBytes, .diskFreePercent: String(localized: "Doluluk oranı")
        case .powerFanSpeed: String(localized: "Fanın en yüksek hıza oranı")
        case .powerTimeRemaining: String(localized: "Pil yüzdesi")
        default: String(localized: "Değer")
        }
        return String(localized: "\(measured) eşiğin \(settings.value.thresholdDirection) öğe turuncuya, kritik eşikte kırmızıya döner.")
    }
}

/// Calm / warning / critical zones along the unit's range, with a marker at the current reading. Drawn in one
/// `Canvas` so the zones always span exactly the width it is given.
private struct ThresholdZones: View {
    let unit: MenuBarThresholdUnit
    let limits: (warning: Double, critical: Double)
    let lowerIsWorse: Bool
    let current: Double?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    private func fraction(_ value: Double) -> CGFloat {
        let span = unit.range.upperBound - unit.range.lowerBound
        return CGFloat(min(1, max(0, (value - unit.range.lowerBound) / span)))
    }

    var body: some View {
        let warning = fraction(limits.warning), critical = fraction(limits.critical)
        // Zone edges from the calm end to the alarming end, mirrored when low values are the bad ones.
        let zones: [(Color, CGFloat, CGFloat)] = lowerIsWorse
            ? [(.red, 0, critical), (.orange, critical, warning), (.green, warning, 1)]
            : [(.green, 0, warning), (.orange, warning, critical), (.red, critical, 1)]
        let marker = current.map(fraction)
        Canvas { context, size in
            let barHeight: CGFloat = 10
            let bar = CGRect(x: 0, y: (size.height - barHeight) / 2, width: size.width, height: barHeight)
            var clipped = context
            clipped.clip(to: Path(roundedRect: bar, cornerRadius: barHeight / 2))
            for zone in zones {
                let rect = CGRect(x: bar.minX + zone.1 * bar.width, y: bar.minY, width: (zone.2 - zone.1) * bar.width, height: barHeight)
                clipped.fill(Path(rect), with: .color(zone.0.opacity(0.85)))
            }
            if differentiate {
                for edge in [warning, critical] {
                    clipped.fill(Path(CGRect(x: bar.minX + edge * bar.width - 1, y: bar.minY, width: 2, height: barHeight)), with: .color(.primary))
                }
            }
            if let marker {
                let x = bar.minX + marker * bar.width
                let thumb = Path(roundedRect: CGRect(x: x - 2, y: 0, width: 4, height: size.height), cornerRadius: 2)
                context.fill(thumb, with: .color(.white))
                context.stroke(thumb, with: .color(.black.opacity(0.55)), lineWidth: 1)
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A pop-up menu picker drawn in the primary text color. The app-wide accent tint made menu labels accent
    /// blue on a pale blue fill, which was hard to read in light mode and washed out in dark mode.
    func pocketMenuPicker() -> some View {
        pickerStyle(.menu).tint(.primary)
    }
}
