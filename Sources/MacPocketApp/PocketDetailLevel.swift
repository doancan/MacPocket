import MacPocketCore
import SwiftUI

/// Basic or advanced view of a menu bar tab. Each tab remembers its own choice; the main window is always advanced.
enum PocketDetailLevel: String, CaseIterable, Identifiable {
    case basic, advanced
    var id: String { rawValue }
    static let defaultValue = PocketDetailLevel.basic

    /// UserDefaults key for one page or tab, e.g. `key("performance")`, `key("menubar.cpu")`.
    static func key(_ scope: String) -> String { "MacPocket.detail.\(scope)" }
}

/// "Gelişmiş" on/off switch for the top-right corner of a menu bar tab. Flipping it animates the
/// advanced sections in and out (they fade while the layout around them resizes).
struct PocketDetailLevelSwitch: View {
    @Binding var level: PocketDetailLevel
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        Toggle("Gelişmiş", isOn: Binding(
            get: { level == .advanced },
            set: { advanced in
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) {
                    level = advanced ? .advanced : .basic
                }
            }))
        .toggleStyle(.switch)
        .fixedSize()
        .help("Kapalıyken özet, açıkken tüm ayrıntılar gösterilir")
    }
}

func pocketCelsius(_ celsius: Double) -> String {
    Measurement(value: celsius, unit: UnitTemperature.celsius)
        .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                numberFormatStyle: .number.precision(.fractionLength(1)))
            .locale(pocketLocale))
}

/// Main-window card: temperature groups, every raw sensor on demand, and SMC power readings.
struct PocketSensorsCard: View {
    let system: SystemSnapshot?
    @ObservedObject private var history = MenuBarHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Sıcaklık ve güç sensörleri", icon: "thermometer.medium") {
                if let readings = system?.temperatures { Text("\(readings.count) sensör") }
            }
            if let system {
                Grid(alignment: .leading, horizontalSpacing: PocketSpacing.l, verticalSpacing: PocketSpacing.s) {
                    if let watts = system.systemPowerWatts {
                        row("Sistem gücü", powerWatts(watts), help: "SMC: Mac’in toplam anlık güç tüketimi")
                    }
                    if let watts = system.powerInputWatts {
                        row("DC giriş gücü", powerWatts(watts), help: "SMC: güç kaynağından gelen giriş gücü; dönüşüm kayıplarını da içerir")
                    }
                    if let fans = system.fans {
                        ForEach(Array(fans.enumerated()), id: \.offset) { index, fan in
                            row("Fan \(index + 1)", MenuBarFormatter.number(fan.rpm, fractionDigits: 0) + " " + MenuBarFormatter.rpmUnit)
                        }
                    }
                    if let readings = system.temperatures {
                        if system.systemPowerWatts != nil || system.powerInputWatts != nil || system.fans?.isEmpty == false {
                            Divider().gridCellColumns(2)
                        }
                        ForEach(TemperatureSummary.groups(readings)) { summary in
                            row("\(summary.group.title)", groupValue(summary),
                                help: "\(summary.count) sensör; en yüksek ve ortalama")
                        }
                    }
                }
                .font(.callout)
                hottestTrend
                if let readings = system.temperatures {
                    DisclosureGroup("Tüm sensörler") {
                        PocketRawSensorList(readings: readings).padding(.top, PocketSpacing.xs)
                    }
                    .font(.callout)
                } else {
                    Text("Bu Mac sıcaklık sensörü yayınlamıyor.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                PocketProgressRow(message: "Sensörler okunuyor…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pocketCard()
    }

    /// The hottest sensor over the samples the menu bar history keeps (about three minutes).
    @ViewBuilder private var hottestTrend: some View {
        let points = history.samples.compactMap { sample in sample.temperature.map { (sample.date, $0) } }
        if points.count >= 2, let first = points.first, let last = points.last,
           let low = points.map(\.1).min(), let high = points.map(\.1).max() {
            let minutes = max(1, Int((last.0.timeIntervalSince(first.0) / 60).rounded()))
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("En sıcak sensör").foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: pocketCelsius(last.1)).monospacedDigit().fontWeight(.semibold)
                }
                PocketSparkline(values: points.map(\.1), color: Self.tint(last.1),
                                ceiling: max(high + 5, low + 15), floor: max(0, low - 5))
                    .frame(height: 44)
                Text("Son \(minutes) dk · en düşük \(pocketCelsius(low)) · en yüksek \(pocketCelsius(high))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
    }

    private static func tint(_ celsius: Double) -> Color {
        celsius >= 90 ? .red : celsius >= 75 ? .orange : .green
    }

    private func groupValue(_ summary: TemperatureGroupSummary) -> String {
        let maximum = pocketCelsius(summary.maximum), average = pocketCelsius(summary.average)
        return summary.count == 1 ? maximum : String(localized: "en yüksek \(maximum) · ort. \(average)")
    }

    private func row(_ title: LocalizedStringKey, _ value: String, help: LocalizedStringKey? = nil) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .help(help ?? "")
    }
}

/// Every sensor as reported, in two columns of name and value.
struct PocketRawSensorList: View {
    let readings: [TemperatureReading]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: PocketSpacing.l), GridItem(.flexible())],
                  alignment: .leading, spacing: PocketSpacing.xs) {
            ForEach(readings, id: \.name) { reading in
                HStack {
                    Text(verbatim: reading.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: PocketSpacing.s)
                    Text(pocketCelsius(reading.celsius)).monospacedDigit()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
