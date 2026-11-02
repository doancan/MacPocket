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
            if service.warmthUnsupported.contains(display.id) {
                PocketMessage("Bu ekranda renk ısıtma uygulanamıyor (HDR açık olabilir). Night Shift yöntemini deneyebilirsin.", tone: .warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

/// A thick filled track in the style of the brightness indicator and Control Center: drag or click anywhere to set
/// the value; the symbol sits on the fill and the percentage (or `valueText`) at the trailing end. Arrow keys /
/// VoiceOver adjust it.
private struct BrightnessFillSlider: View {
    let title: LocalizedStringKey
    let symbol: String
    /// 0…1.
    let value: Double
    let height: CGFloat
    /// Shown instead of the percentage.
    var valueText: String?
    var fill = AnyShapeStyle(PocketTheme.brand)
    let set: (Double) -> Void

    private var label: String { valueText ?? pocketPercent(value * 100) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Never narrower than the track is tall, so the symbol stays on the fill even at 0 %.
            let fill = height + (width - height) * min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(self.fill).frame(width: fill)
                Image(systemName: symbol)
                    .font(.system(size: height * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: height, height: height)
                Text(verbatim: label)
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
        .accessibilityValue(Text(verbatim: label))
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

/// Brightness by time of day: the manual points with their 24-hour curve, or night mode following the sun.
private struct BrightnessScheduleCard: View {
    @ObservedObject var service: DisplayBrightnessService
    @ObservedObject private var night = NightModeService.shared

    var body: some View {
        let schedule = service.schedule
        let solar = schedule.source == .solar
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Zaman çizelgesi", icon: "clock") {
                HStack(spacing: PocketSpacing.m) {
                    if schedule.enabled && solar { NightStatusBadge(status: night.status) }
                    Toggle("Zaman çizelgesi", isOn: Binding(get: { schedule.enabled }, set: { service.schedule.enabled = $0 }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            Picker("Çizelge kaynağı", selection: Binding(get: { schedule.source ?? .manual }, set: { service.schedule.source = $0 })) {
                ForEach([BrightnessSchedule.Source.manual, .solar], id: \.self) { source in
                    Text(source.localizedTitle).tag(source)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Text(solar
                 ? "Gün batımında harici ekranlar yavaşça kararır ve rengi ısınır; gün doğumunda her ekran kendi gündüz parlaklığına döner."
                 : "Harici ekranların parlaklığı günün saatine göre yumuşakça değişir. Elle değiştirdiğinde çizelge bir sonraki noktaya kadar bekler.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if solar {
                NightScheduleSection(service: service, night: night)
            } else {
                manualPoints(schedule)
            }
            if let until = service.overrideUntil, schedule.enabled {
                Text("Elle ayarlandı; \(until.formatted(date: .omitted, time: .shortened))’de çizelgeye döner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    @ViewBuilder private func manualPoints(_ schedule: BrightnessSchedule) -> some View {
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
        Button { service.schedule.points.append(.init(minute: (DisplayBrightnessService.currentMinute + 60) % 1440, level: 0.7)) } label: {
            Label("Nokta ekle", systemImage: "plus")
        }
    }

    private static func date(minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Night mode's state next to the schedule switch.
private struct NightStatusBadge: View {
    let status: NightModeService.Status

    var body: some View {
        switch status {
        case .off:
            EmptyView()
        case .needsLocation:
            PocketStatusBadge(text: "Konum gerekli", systemImage: "location.slash", tone: .warning)
        case .paused:
            PocketStatusBadge(text: "Duraklatıldı", systemImage: "pause.circle.fill", tone: .warning)
        case let .active(target):
            if target.night >= 0.999 {
                PocketStatusBadge(text: "Gece", systemImage: "moon.fill", tone: .accent)
            } else if target.night > 0.001 {
                PocketStatusBadge(text: "Geçişte", systemImage: "circle.lefthalf.filled", tone: .accent)
            } else {
                PocketStatusBadge(text: "Gündüz", systemImage: "sun.max.fill", tone: .success)
            }
        }
    }
}

/// "Follow the sun": location and today's sun times, the night curve, brightness and colour, and the exceptions.
private struct NightScheduleSection: View {
    @ObservedObject var service: DisplayBrightnessService
    @ObservedObject var night: NightModeService
    @ObservedObject private var location: NightLocationProvider
    @State private var choosingCity = false

    private static let minKelvin = 1900.0
    private static let maxKelvin = 6500.0

    init(service: DisplayBrightnessService, night: NightModeService) {
        self.service = service
        self.night = night
        _location = ObservedObject(wrappedValue: night.location)
    }

    private var settings: NightSettings { service.schedule.night ?? NightSettings() }

    private func binding<Value>(_ keyPath: WritableKeyPath<NightSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in night.updateNight { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        let settings = self.settings
        let now = night.debugNow ?? Date()
        VStack(alignment: .leading, spacing: 0) {
            locationRow(settings)
            if let coordinate = settings.location {
                let day = SolarCalculator.day(containing: now, at: coordinate, timeZone: .current)
                SunTimes(day: day).padding(.bottom, PocketSpacing.m)
                NightCurveChart(day: day, settings: settings, now: now)
                    .frame(height: 160)
                    .opacity(service.schedule.enabled ? 1 : 0.45)
                    .padding(.bottom, PocketSpacing.m)
            }
            Divider()
            BrightnessSettingRow("Parlaklığı düşür", detail: "Her ekran gece kendi gündüz parlaklığının bu oranına iner.") {
                Toggle("Parlaklığı düşür", isOn: binding(\.dimBrightness)).toggleStyle(.switch).labelsHidden()
            }
            if settings.dimBrightness {
                BrightnessFillSlider(title: "Gece parlaklığı", symbol: "moon.fill", value: settings.nightLevel, height: 28) { value in
                    night.updateNight { $0.nightLevel = (value * 100).rounded() / 100 }
                }
                .padding(.bottom, PocketSpacing.m)
            }
            Divider()
            BrightnessSettingRow("Rengi ısıt", detail: "Mavi ışığı azaltmak için ekranın rengi gece sıcak tonlara kayar.") {
                Toggle("Rengi ısıt", isOn: binding(\.warmColor)).toggleStyle(.switch).labelsHidden()
            }
            if settings.warmColor {
                VStack(alignment: .leading, spacing: PocketSpacing.m) {
                    BrightnessFillSlider(title: "Gece renk sıcaklığı", symbol: "thermometer.sun.fill",
                                         value: (settings.nightKelvin - Self.minKelvin) / (Self.maxKelvin - Self.minKelvin), height: 28,
                                         valueText: "\(Int(settings.nightKelvin.rounded())) K",
                                         fill: AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.12), Color(red: 1, green: 0.78, blue: 0.4)],
                                                                            startPoint: .leading, endPoint: .trailing))) { value in
                        let kelvin = Self.minKelvin + value * (Self.maxKelvin - Self.minKelvin)
                        night.updateNight { $0.nightKelvin = min(max((kelvin / 100).rounded() * 100, Self.minKelvin), Self.maxKelvin) }
                    }
                    HStack {
                        Text("Daha sıcak")
                        Spacer()
                        Text("Nötr")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Text("Renk yöntemi").padding(.top, PocketSpacing.xs)
                    ColorMethodPicker(selection: binding(\.colorMethod), nightShiftAvailable: night.nightShiftAvailable)
                }
                .padding(.bottom, PocketSpacing.m)
            }
            Divider()
            BrightnessSettingRow("Geçiş süresi", detail: "Gün batımı çevresinde kararmanın sürdüğü zaman; gün doğumu 30 dakikada tamamlanır.") {
                Picker("Geçiş süresi", selection: binding(\.transitionMinutes)) {
                    Text("20 dk").tag(20)
                    Text("1 saat").tag(60)
                    Text("2 saat").tag(120)
                }
                .labelsHidden().fixedSize()
            }
            exceptions(settings, now: now)
        }
    }

    // MARK: Location

    @ViewBuilder private func locationRow(_ settings: NightSettings) -> some View {
        let denied = location.authorization == .denied || location.authorization == .restricted
        HStack(spacing: PocketSpacing.m) {
            PocketIconTile(symbol: settings.location == nil ? "location.slash.fill" : "location.fill", tint: PocketTheme.brand, size: 30)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                if let name = settings.locationName {
                    Text(verbatim: name).font(.headline)
                } else if let coordinate = settings.location {
                    Text(verbatim: "\(coordinate.latitude.formatted(.number.precision(.fractionLength(2)).locale(pocketLocale))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(2)).locale(pocketLocale)))")
                        .font(.headline).monospacedDigit()
                } else {
                    Text("Konum seçilmedi").font(.headline)
                }
                Text("Gün doğumu ve batımı bu konuma göre hesaplanır.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: PocketSpacing.m)
            if !denied {
                Button { night.useCurrentLocation() } label: { Label("Konumu kullan", systemImage: "location.fill") }
            }
            Button { choosingCity = true } label: { Label("Şehir seç…", systemImage: "building.2") }
                .popover(isPresented: $choosingCity, arrowEdge: .bottom) {
                    CityPickerList(selectedName: settings.locationName) { city in
                        night.updateNight {
                            $0.location = city.coordinate
                            $0.locationName = city.name
                        }
                        choosingCity = false
                    }
                }
        }
        .padding(.vertical, PocketSpacing.m)
        if denied {
            HStack(spacing: PocketSpacing.m) {
                PocketMessage("Konum izni kapalı. Sistem Ayarları’ndan izin verebilir ya da listeden bir şehir seçebilirsin.", tone: .warning)
                Button("Sistem Ayarları…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
            .padding(.bottom, PocketSpacing.m)
        } else if settings.location == nil {
            PocketMessage("Konum bekleniyor. Konum iznini vermek istemezsen listeden bir şehir seç.", tone: .neutral)
                .padding(.bottom, PocketSpacing.m)
        }
    }

    // MARK: Exceptions

    @ViewBuilder private func exceptions(_ settings: NightSettings, now: Date) -> some View {
        PocketSectionHeader("İstisnalar", icon: "pause.circle")
            .padding(.top, PocketSpacing.l)
            .padding(.bottom, PocketSpacing.xs)
        if let until = settings.pausedUntil, until > now {
            BrightnessSettingRow("Gece modu duraklatıldı", detail: "Yeniden açılma: \(until.formatted(date: .omitted, time: .shortened))") {
                Button { night.resume() } label: { Label("Yeniden aç", systemImage: "play.fill") }
            }
        } else {
            BrightnessSettingRow("Bir saatliğine kapat", detail: "Parlaklık ve renk hemen normale döner; bir saat sonra gece modu kendiliğinden geri gelir.") {
                Button { night.pauseForAnHour() } label: { Label("Bir saatliğine kapat", systemImage: "pause.fill") }
                    .disabled(!service.schedule.enabled)
            }
        }
        Divider()
        BrightnessSettingRow("Tam ekran video oynarken kapat", detail: "Öndeki uygulama tam ekranda video oynatırken ekran normal görünür.") {
            Toggle("Tam ekran video oynarken kapat", isOn: binding(\.pauseForFullScreenVideo)).toggleStyle(.switch).labelsHidden()
        }
        Divider()
        BrightnessSettingRow("Bu uygulamalar öndeyken kapat", detail: "Uygulama öne geldiğinde ekran normale döner, ayrıldığında gece moduna geri geçer.") {
            Button { addApplications() } label: { Label("Ekle…", systemImage: "plus") }
        }
        ForEach(settings.excludedApps, id: \.self) { bundleID in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
            HStack(spacing: PocketSpacing.m) {
                PocketAppIcon(url: url, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: name)
                    Text(verbatim: bundleID).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { night.updateNight { $0.excludedApps.removeAll { $0 == bundleID } } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(name) uygulamasını listeden çıkar")
            }
            .padding(.vertical, PocketSpacing.xs)
            .padding(.horizontal, PocketSpacing.s)
            .background(PocketTheme.raised, in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
            .padding(.bottom, PocketSpacing.xs)
        }
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        night.updateNight { settings in
            for id in ids where !settings.excludedApps.contains(id) { settings.excludedApps.append(id) }
        }
    }
}

/// Today's sunrise and sunset as two small tiles, or the polar day/night note.
private struct SunTimes: View {
    let day: SolarDay

    var body: some View {
        switch day {
        case let .normal(sunrise, sunset):
            HStack(spacing: PocketSpacing.m) {
                tile(symbol: "sunrise.fill", title: "Gün doğumu", time: sunrise)
                tile(symbol: "sunset.fill", title: "Gün batımı", time: sunset)
            }
        case .alwaysDay:
            Label("Güneş bugün batmıyor; gece modu uygulanmaz.", systemImage: "sun.max.fill")
                .foregroundStyle(.secondary)
        case .alwaysNight:
            Label("Güneş bugün doğmuyor; gün boyu gece değerleri uygulanır.", systemImage: "moon.stars.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func tile(symbol: String, title: LocalizedStringKey, time: Date) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: time.formatted(date: .omitted, time: .shortened))
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, PocketSpacing.m)
        .padding(.vertical, PocketSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PocketTheme.raised, in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Today's night curve from `NightCurve`: brightness as a filled line (relative to each display's day level) and,
/// when warming is on, the colour temperature as a strip under it.
private struct NightCurveChart: View {
    let day: SolarDay
    let settings: NightSettings
    let now: Date

    private struct Sample: Identifiable {
        let id: Int
        let hour: Double
        let brightness: Double
        /// 0 neutral … 1 the warmest temperature the slider allows.
        let warmth: Double
    }

    private static let stripBottom = -13.0
    private static let stripTop = -5.0

    var body: some View {
        let start = Calendar.current.startOfDay(for: now)
        let samples = stride(from: 0, through: 1440, by: 10).map { minute in
            let target = NightCurve.target(at: start.addingTimeInterval(Double(minute) * 60), day: day, settings: settings)
            return Sample(id: minute, hour: Double(minute) / 60,
                          brightness: settings.dimBrightness ? target.level * 100 : 100,
                          warmth: min(max((6500 - target.kelvin) / (6500 - 1900), 0), 1))
        }
        let hour = { (date: Date) in date.timeIntervalSince(start) / 3600 }
        Chart {
            if settings.warmColor {
                RectangleMark(xStart: .value(Text("Saat"), 0), xEnd: .value(Text("Saat"), 24),
                              yStart: .value(Text("Renk"), Self.stripBottom), yEnd: .value(Text("Renk"), Self.stripTop))
                    .foregroundStyle(Color.primary.opacity(0.07))
                ForEach(samples.dropLast()) { sample in
                    RectangleMark(xStart: .value(Text("Saat"), sample.hour), xEnd: .value(Text("Saat"), sample.hour + 1.0 / 6),
                                  yStart: .value(Text("Renk"), Self.stripBottom), yEnd: .value(Text("Renk"), Self.stripTop))
                        .foregroundStyle(Color.orange.opacity(sample.warmth))
                }
            }
            ForEach(samples) { sample in
                AreaMark(x: .value(Text("Saat"), sample.hour), yStart: .value(Text("Parlaklık"), 0), yEnd: .value(Text("Parlaklık"), sample.brightness))
                    .interpolationMethod(.linear)
                    .foregroundStyle(LinearGradient(colors: [PocketTheme.brand.opacity(0.28), PocketTheme.brand.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(samples) { sample in
                LineMark(x: .value(Text("Saat"), sample.hour), y: .value(Text("Parlaklık"), sample.brightness))
                    .interpolationMethod(.linear)
                    .foregroundStyle(PocketTheme.brand)
            }
            if case let .normal(sunrise, sunset) = day {
                ForEach([(sunrise, "sunrise.fill"), (sunset, "sunset.fill")], id: \.1) { date, symbol in
                    if (0...24).contains(hour(date)) {
                        RuleMark(x: .value(Text("Saat"), hour(date)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .annotation(position: .top, spacing: 2) {
                                Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.caption)
                            }
                    }
                }
            }
            RuleMark(x: .value(Text("Şimdi"), hour(now)))
                .foregroundStyle(.orange.opacity(0.7))
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: (settings.warmColor ? Self.stripBottom : 0)...100)
        .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 24]) { value in AxisGridLine(); AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0):00") } } }
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in AxisGridLine(); AxisValueLabel { Text(verbatim: pocketPercent(value.as(Double.self) ?? 0)) } } }
        .accessibilityLabel("Günlük gece modu eğrisi")
    }
}

/// The colour method as two tiles; Night Shift is disabled with an explanation where macOS doesn't offer it.
private struct ColorMethodPicker: View {
    @Binding var selection: ColorMethod
    let nightShiftAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                tile(.macPocket, symbol: "paintpalette.fill", detail: "Her harici ekranın renk tablosunu MacPocket ısıtır.")
                tile(.nightShift, symbol: "moon.circle.fill", detail: "Rengi macOS’un Night Shift’i ısıtır; önceki Night Shift ayarın sonra geri gelir.")
                    .disabled(!nightShiftAvailable)
                    .opacity(nightShiftAvailable ? 1 : 0.45)
            }
            if !nightShiftAvailable {
                Text("Night Shift bu Mac’te kullanılamıyor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ method: ColorMethod, symbol: String, detail: LocalizedStringKey) -> some View {
        let selected = selection == method
        return Button { selection = method } label: {
            HStack(alignment: .top, spacing: PocketSpacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? PocketTheme.brand : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text(method.localizedTitle).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(PocketSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(PocketTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? PocketTheme.brand : PocketTheme.line, lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(method.localizedTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Searchable list of the embedded cities, sorted for the current language.
private struct CityPickerList: View {
    let selectedName: String?
    let select: (City) -> Void
    @State private var query = ""

    private static let cities = CityCatalog.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    private var filtered: [City] {
        query.isEmpty ? Self.cities : Self.cities.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSearchField("Şehir ara", text: $query)
            if filtered.isEmpty {
                Text("Eşleşen şehir yok").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { city in
                    Button { select(city) } label: {
                        HStack {
                            Text(verbatim: city.name)
                            Spacer()
                            if city.name == selectedName { Image(systemName: "checkmark").foregroundStyle(PocketTheme.brand) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .padding(PocketSpacing.m)
        .frame(width: 260, height: 340)
    }
}

extension BrightnessSchedule.Source {
    var localizedTitle: String {
        switch self {
        case .manual: String(localized: "Elle saatler")
        case .solar: String(localized: "Güneşe göre")
        }
    }
}

extension ColorMethod {
    var localizedTitle: String {
        switch self {
        case .macPocket: String(localized: "MacPocket")
        case .nightShift: String(localized: "macOS Night Shift")
        }
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
