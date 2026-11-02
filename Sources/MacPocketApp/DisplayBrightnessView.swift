import AppKit
import ApplicationServices
import MacPocketCore
import Charts
import SwiftUI

/// Tools → Ekran Parlaklığı: per-display brightness and contrast for external monitors, and the keyboard keys.
struct DisplayBrightnessView: View {
    @ObservedObject private var service = DisplayBrightnessService.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekran Parlaklığı",
                              subtitle: "Harici monitörlerin parlaklığını klavyenin parlaklık tuşlarıyla, dahili ekran gibi ayarla.",
                              icon: "sun.max.fill") {
                Button { Task { await service.refreshDisplays() } } label: { Label("Yeniden algıla", systemImage: "arrow.clockwise") }
                    .disabled(service.detecting)
            }
            if service.settings.keysEnabled && !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Parlaklık tuşlarını yakalamak için Erişilebilirlik izni gerekir. İzin verdikten sonra MacPocket’e dönmen yeterli.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if service.displays.isEmpty {
                        ContentUnavailableView(service.detecting ? "Ekranlar algılanıyor…" : "Harici ekran yok",
                                               systemImage: "display",
                                               description: Text("Dahili ekranın parlaklığını macOS yönetir."))
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .pocketCard()
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: PocketSpacing.l, alignment: .top)],
                              alignment: .leading, spacing: PocketSpacing.l) {
                        ForEach(service.displays) { display in DisplayCard(display: display, service: service) }
                    }
                    keys
                    BrightnessScheduleCard(service: service)
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private var indicatorPosition: Binding<DisplayBrightnessService.IndicatorPosition> {
        Binding(get: { service.settings.indicatorPosition ?? .topRight },
                set: { service.settings.indicatorPosition = $0; service.previewIndicator() })
    }

    private var indicatorStyle: Binding<DisplayBrightnessService.IndicatorStyle> {
        Binding(get: { service.settings.indicatorStyle ?? .modern },
                set: { service.settings.indicatorStyle = $0; service.previewIndicator() })
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 0) {
            PocketSectionHeader("Klavye", icon: "keyboard") {
                if service.tapActive {
                    PocketStatusBadge(text: "Etkin", systemImage: "checkmark.circle.fill", tone: .success)
                }
            }
            .padding(.bottom, PocketSpacing.s)
            BrightnessSettingRow("Parlaklık tuşları harici ekranları da ayarlasın",
                                 detail: "Dahili gibi 16 adımda değişir; ⌥⇧ ile birlikte basınca dörtte bir adım ilerler. İmleç dahili ekrandayken tuşlar her zamanki gibi macOS’a gider.") {
                Toggle("Parlaklık tuşları harici ekranları da ayarlasın", isOn: $service.settings.keysEnabled)
                    .toggleStyle(.switch).labelsHidden()
            }
            Divider()
            BrightnessSettingRow("Hangi ekran") {
                Picker("Hangi ekran", selection: $service.settings.target) {
                    Text("İmlecin bulunduğu ekran").tag(DisplayBrightnessService.Target.underPointer)
                    Text("Tüm harici ekranlar").tag(DisplayBrightnessService.Target.allExternal)
                    Text("Ana ekran").tag(DisplayBrightnessService.Target.main)
                }
                .labelsHidden().fixedSize()
            }
            .disabled(!service.settings.keysEnabled)
            Divider()
            BrightnessSettingRow("Parlaklık göstergesini göster") {
                Toggle("Parlaklık göstergesini göster", isOn: $service.settings.showIndicator)
                    .toggleStyle(.switch).labelsHidden()
            }
            .disabled(!service.settings.keysEnabled)
            Divider()
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                Text("Gösterge stili")
                IndicatorStylePicker(selection: indicatorStyle)
                if !(indicatorStyle.wrappedValue == .classic && BrightnessIndicator.classicIsSystemBezel) {
                    Text("Gösterge konumu").padding(.top, PocketSpacing.s)
                    IndicatorPositionPicker(selection: indicatorPosition, style: indicatorStyle.wrappedValue)
                }
            }
            .padding(.vertical, PocketSpacing.m)
            .disabled(!service.settings.keysEnabled || !service.settings.showIndicator)
            .opacity(service.settings.keysEnabled && service.settings.showIndicator ? 1 : 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

/// The two indicator styles drawn as small samples.
private struct IndicatorStylePicker: View {
    @Binding var selection: DisplayBrightnessService.IndicatorStyle

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            ForEach(DisplayBrightnessService.IndicatorStyle.allCases, id: \.self) { style in
                Button { selection = style } label: { tile(style) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(style.localizedTitle))
                    .accessibilityAddTraits(selection == style ? .isSelected : [])
            }
        }
    }

    private func tile(_ style: DisplayBrightnessService.IndicatorStyle) -> some View {
        let selected = selection == style
        return VStack(spacing: PocketSpacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PocketTheme.raised)
                switch style {
                case .modern:
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Capsule().fill(Color.primary.opacity(0.5)).frame(width: 34, height: 4)
                            Spacer()
                            Capsule().fill(Color.primary.opacity(0.3)).frame(width: 14, height: 4)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(selected ? PocketTheme.brand : Color.primary.opacity(0.6)).frame(width: 58)
                            Image(systemName: "sun.max.fill").font(.system(size: 6, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 11, height: 11)
                        }
                        .frame(height: 11)
                    }
                    .padding(9)
                    .frame(width: 104, height: 40)
                    .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                case .capsule:
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max.fill").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(selected ? PocketTheme.brand : Color.primary.opacity(0.7))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.15))
                            Capsule().fill(selected ? PocketTheme.brand : Color.primary.opacity(0.6)).frame(width: 40)
                        }
                        .frame(height: 3)
                        Capsule().fill(Color.primary.opacity(0.4)).frame(width: 12, height: 4)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 104, height: 24)
                    .background(.background, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                case .classic:
                    VStack(spacing: 6) {
                        Image(systemName: "sun.max.fill").font(.system(size: 20))
                            .foregroundStyle(selected ? PocketTheme.brand : Color.primary.opacity(0.7))
                        HStack(spacing: 1) {
                            ForEach(0..<8, id: \.self) { index in
                                Rectangle().fill(index < 5 ? Color.primary.opacity(0.7) : Color.primary.opacity(0.15)).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? PocketTheme.brand : PocketTheme.line, lineWidth: selected ? 2 : 1)
            }
            .frame(width: 140, height: 76)
            Text(style.localizedTitle)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Indicator position as miniature screens: each tile draws the screen with its menu bar and the indicator where it
/// would appear. Choosing one previews the real indicator.
private struct IndicatorPositionPicker: View {
    @Binding var selection: DisplayBrightnessService.IndicatorPosition
    let style: DisplayBrightnessService.IndicatorStyle

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            ForEach(DisplayBrightnessService.IndicatorPosition.allCases, id: \.self) { position in
                Button { selection = position } label: { tile(position) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(position.localizedTitle))
                    .accessibilityAddTraits(selection == position ? .isSelected : [])
            }
        }
    }

    private func tile(_ position: DisplayBrightnessService.IndicatorPosition) -> some View {
        let selected = selection == position
        return VStack(spacing: PocketSpacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [PocketTheme.brand.opacity(0.22), PocketTheme.brandSecondary.opacity(0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(spacing: 0) {
                    Rectangle().fill(Color.primary.opacity(0.14)).frame(height: 6) // menu bar
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: style == .classic ? 3 : 4.5, style: .continuous)
                    .fill(selected ? PocketTheme.brand : Color.primary.opacity(0.45))
                    .frame(width: style == .classic ? 18 : 34, height: style == .classic ? 18 : (style == .capsule ? 7 : 9))
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(position))
                    .padding(.top, position == .center || position == .bottomCenter ? 6 : 11)
                    .padding(.bottom, position == .bottomCenter ? 12 : 6)
                    .padding(.horizontal, 7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? PocketTheme.brand : PocketTheme.line, lineWidth: selected ? 2 : 1)
            }
            .frame(width: 112, height: 70)
            Text(position.localizedTitle)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    private static func alignment(_ position: DisplayBrightnessService.IndicatorPosition) -> Alignment {
        switch position {
        case .topRight: .topTrailing
        case .topCenter: .top
        case .bottomCenter: .bottom
        case .center: .center
        }
    }
}

/// A System Settings style row: title (and optional explanation) on the left, the control on the right.
private struct BrightnessSettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @ViewBuilder let control: Control

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                Text(title)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: PocketSpacing.l)
            control
        }
        .padding(.vertical, PocketSpacing.m)
    }
}

private struct DisplayCard: View {
    let display: DisplayBrightnessService.ManagedDisplay
    @ObservedObject var service: DisplayBrightnessService

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: "display", tint: PocketTheme.brand, size: 34)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(display.name).font(.headline).lineLimit(1)
                    Group {
                        if display.active == .hardware {
                            Label("Donanım (DDC)", systemImage: "cpu")
                                .help("Monitörün kendi arka ışığı değişir.")
                        } else {
                            Label("Yazılım", systemImage: "circle.lefthalf.filled")
                                .help("Görüntü karartılır; arka ışık aynı kalır.")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: PocketSpacing.s)
                Picker("Yöntem", selection: Binding(get: { service.settings.methods[display.key] ?? .automatic },
                                                    set: { service.settings.methods[display.key] = $0 })) {
                    Text("Otomatik").tag(DisplayBrightnessService.Method.automatic)
                    Text("Donanım (DDC)").tag(DisplayBrightnessService.Method.hardware)
                    Text("Yazılım").tag(DisplayBrightnessService.Method.software)
                }
                .labelsHidden()
                .fixedSize()
            }
            BrightnessFillSlider(title: "Parlaklık", symbol: display.level < 0.5 ? "sun.min.fill" : "sun.max.fill",
                                 value: display.level, height: 34) { service.setLevel($0, for: display.id) }
            if let contrast = display.contrast {
                BrightnessFillSlider(title: "Kontrast", symbol: "circle.righthalf.filled",
                                     value: contrast, height: 24) { service.setContrast($0, for: display.id) }
            }
            if !display.hardwareAvailable {
                Text("Bu monitör DDC/CI ile parlaklık bildirmedi. Monitörün kendi menüsünde DDC/CI açıksa “Donanım (DDC)” seçebilirsin; kapalıysa yazılımsal karartma kullanılır.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

/// A thick filled track in the style of the brightness indicator and Control Center: drag or click anywhere to set
/// the value; the symbol sits on the fill and the percentage at the trailing end. Arrow keys / VoiceOver adjust it.
private struct BrightnessFillSlider: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: Double
    let height: CGFloat
    let set: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Never narrower than the track is tall, so the symbol stays on the fill even at 0 %.
            let fill = height + (width - height) * min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(PocketTheme.brand).frame(width: fill)
                Image(systemName: symbol)
                    .font(.system(size: height * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: height, height: height)
                Text(verbatim: pocketPercent(value * 100))
                    .font(.system(size: max(11, height * 0.36), weight: .semibold).monospacedDigit())
                    .foregroundStyle(value > 0.9 ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, height * 0.4)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                set(min(1, max(0, (drag.location.x - height / 2) / max(1, width - height))))
            })
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: pocketPercent(value * 100)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(BrightnessStep.next(from: value, up: true, step: BrightnessStep.normal))
            case .decrement: set(BrightnessStep.next(from: value, up: false, step: BrightnessStep.normal))
            @unknown default: break
            }
        }
        .help(Text(title))
    }
}

/// Brightness by time of day, with the 24-hour curve drawn from the same interpolation that drives it.
private struct BrightnessScheduleCard: View {
    @ObservedObject var service: DisplayBrightnessService

    var body: some View {
        let schedule = service.schedule
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Zaman çizelgesi", icon: "clock") {
                Toggle("Zaman çizelgesi", isOn: Binding(get: { schedule.enabled }, set: { service.schedule.enabled = $0 }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Text("Harici ekranların parlaklığı günün saatine göre yumuşakça değişir. Elle değiştirdiğinde çizelge bir sonraki noktaya kadar bekler.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Chart {
                ForEach(Array(stride(from: 0, through: 1440, by: 20)), id: \.self) { minute in
                    LineMark(x: .value(Text("Saat"), Double(minute) / 60), y: .value(Text("Parlaklık"), (schedule.level(at: minute % 1440) ?? 1) * 100))
                        .interpolationMethod(.linear)
                        .foregroundStyle(PocketTheme.brand)
                }
                ForEach(schedule.points) { point in
                    PointMark(x: .value(Text("Saat"), Double(point.minute) / 60), y: .value(Text("Parlaklık"), point.level * 100))
                        .foregroundStyle(PocketTheme.brand)
                }
                RuleMark(x: .value(Text("Şimdi"), Double(DisplayBrightnessService.currentMinute) / 60))
                    .foregroundStyle(.orange.opacity(0.7))
            }
            .chartXScale(domain: 0...24)
            .chartYScale(domain: 0...100)
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 24]) { value in AxisGridLine(); AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0):00") } } }
            .frame(height: 140)
            .opacity(schedule.enabled ? 1 : 0.45)
            .accessibilityLabel("Günlük parlaklık eğrisi")
            ForEach(schedule.points.indices, id: \.self) { index in
                HStack(spacing: PocketSpacing.m) {
                    DatePicker("Saat", selection: Binding(get: { Self.date(minute: schedule.points[index].minute) },
                                                         set: { service.schedule.points[index].minute = Self.minute(of: $0) }),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Slider(value: Binding(get: { schedule.points[index].level }, set: { service.schedule.points[index].level = $0 }), in: 0...1) {
                        Text("Parlaklık")
                    }
                    .labelsHidden()
                    Text(verbatim: pocketPercent(schedule.points[index].level * 100)).monospacedDigit().frame(width: 48, alignment: .trailing)
                    Button { service.schedule.points.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .disabled(schedule.points.count <= 1)
                        .accessibilityLabel("Noktayı sil")
                }
            }
            HStack {
                Button { service.schedule.points.append(.init(minute: (DisplayBrightnessService.currentMinute + 60) % 1440, level: 0.7)) } label: {
                    Label("Nokta ekle", systemImage: "plus")
                }
                Spacer()
                if let until = service.overrideUntil, schedule.enabled {
                    Text("Elle ayarlandı; \(until.formatted(date: .omitted, time: .shortened))’de çizelgeye döner.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private static func date(minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

extension DisplayBrightnessService.IndicatorPosition {
    var localizedTitle: String {
        switch self {
        case .topRight: String(localized: "Sağ üst")
        case .topCenter: String(localized: "Üst orta")
        case .bottomCenter: String(localized: "Alt orta")
        case .center: String(localized: "Ekranın ortası")
        }
    }
}

extension DisplayBrightnessService.IndicatorStyle {
    var localizedTitle: String {
        switch self {
        case .modern: String(localized: "Modern")
        case .capsule: String(localized: "Kapsül")
        case .classic: String(localized: "Klasik (macOS)")
        }
    }
}
