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
                    ForEach(service.displays) { display in DisplayCard(display: display, service: service) }
                    BrightnessScheduleCard(service: service)
                    keys
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Klavye", icon: "keyboard") {
                if service.tapActive {
                    PocketStatusBadge(text: "Etkin", systemImage: "checkmark.circle.fill", tone: .success)
                }
            }
            Toggle("Parlaklık tuşları harici ekranları da ayarlasın", isOn: $service.settings.keysEnabled)
            Picker("Hangi ekran", selection: $service.settings.target) {
                Text("İmlecin bulunduğu ekran").tag(DisplayBrightnessService.Target.underPointer)
                Text("Tüm harici ekranlar").tag(DisplayBrightnessService.Target.allExternal)
                Text("Ana ekran").tag(DisplayBrightnessService.Target.main)
            }
            .frame(maxWidth: 380)
            .disabled(!service.settings.keysEnabled)
            Toggle("macOS parlaklık göstergesini göster", isOn: $service.settings.showIndicator)
                .disabled(!service.settings.keysEnabled || !BrightnessIndicator.isNative)
            Text("Dahili gibi 16 adımda değişir; ⌥⇧ ile birlikte basınca dörtte bir adım ilerler. İmleç dahili ekrandayken tuşlar her zamanki gibi macOS’a gider.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

private struct DisplayCard: View {
    let display: DisplayBrightnessService.ManagedDisplay
    @ObservedObject var service: DisplayBrightnessService

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                PocketIconTile(symbol: "display", tint: PocketTheme.brand, size: 28)
                Text(display.name).font(.title3.weight(.semibold))
                if display.active == .hardware {
                    PocketStatusBadge(text: "Donanım (DDC)", systemImage: "cpu", tone: .success)
                        .help("Monitörün kendi arka ışığı değişir.")
                } else {
                    PocketStatusBadge(text: "Yazılım", systemImage: "circle.lefthalf.filled", tone: .neutral)
                        .help("Görüntü karartılır; arka ışık aynı kalır.")
                }
                Spacer()
                Picker("Yöntem", selection: Binding(get: { service.settings.methods[display.key] ?? .automatic },
                                                    set: { service.settings.methods[display.key] = $0 })) {
                    Text("Otomatik").tag(DisplayBrightnessService.Method.automatic)
                    Text("Donanım (DDC)").tag(DisplayBrightnessService.Method.hardware)
                    Text("Yazılım").tag(DisplayBrightnessService.Method.software)
                }
                .labelsHidden()
                .fixedSize()
            }
            slider("Parlaklık", symbol: "sun.max", value: display.level) { service.setLevel($0, for: display.id) }
            if let contrast = display.contrast {
                slider("Kontrast", symbol: "circle.righthalf.filled", value: contrast) { service.setContrast($0, for: display.id) }
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

    private func slider(_ title: LocalizedStringKey, symbol: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Label(title, systemImage: symbol).frame(width: 120, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: 0...1) { Text(title) }
                .labelsHidden()
            Text(verbatim: pocketPercent(value * 100)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
        }
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
