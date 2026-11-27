import MacPocketCore
import SwiftUI

/// Tools → Güç Zamanlaması: repeating wake/power-on and sleep/shutdown times, plus one-time events, through
/// `pmset`.
@MainActor
final class PowerScheduleModel: ObservableObject {
    @Published private(set) var snapshot = PowerScheduleSnapshot()
    @Published var onEnabled = false
    @Published var onKind = PowerEventKind.wakeOrPowerOn
    @Published var onTime = PowerScheduleModel.date(minutes: 8 * 60)
    @Published var onDays = PowerWeekdays.weekdays
    @Published var offEnabled = false
    @Published var offKind = PowerEventKind.sleep
    @Published var offTime = PowerScheduleModel.date(minutes: 23 * 60)
    @Published var offDays = PowerWeekdays.everyDay
    @Published var oneTimeKind = PowerEventKind.wake
    @Published var oneTimeDate = Date().addingTimeInterval(3600)
    @Published private(set) var busy = false
    @Published private(set) var message: (text: String, tone: PocketTone)?

    init() { reload(adoptRepeating: true) }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var pendingOn: RepeatingPowerEvent? { onEnabled ? RepeatingPowerEvent(kind: onKind, minutes: Self.minutes(onTime), days: onDays) : nil }
    var pendingOff: RepeatingPowerEvent? { offEnabled ? RepeatingPowerEvent(kind: offKind, minutes: Self.minutes(offTime), days: offDays) : nil }
    var hasChanges: Bool { pendingOn != snapshot.powerOn || pendingOff != snapshot.powerOff }

    func reload(adoptRepeating: Bool = false) {
        snapshot = PowerScheduleReader.read()
        guard adoptRepeating else { return }
        if let on = snapshot.powerOn {
            onEnabled = true
            onKind = on.kind
            onTime = Self.date(minutes: on.minutes)
            onDays = on.days
        } else { onEnabled = false }
        if let off = snapshot.powerOff {
            offEnabled = true
            offKind = off.kind
            offTime = Self.date(minutes: off.minutes)
            offDays = off.days
        } else { offEnabled = false }
    }

    func applyRepeating() {
        run(PowerScheduleCommand.repeating(on: pendingOn, off: pendingOff),
            success: pendingOn == nil && pendingOff == nil ? String(localized: "Tekrarlayan program kaldırıldı.") : String(localized: "Tekrarlayan program kaydedildi."))
    }

    func addOneTime() {
        guard oneTimeDate > Date().addingTimeInterval(30) else {
            message = (String(localized: "Gelecekte bir zaman seç."), .warning)
            return
        }
        run(PowerScheduleCommand.schedule(oneTimeKind, at: oneTimeDate), success: String(localized: "Olay eklendi."))
    }

    func cancel(_ event: ScheduledPowerEvent) {
        run(PowerScheduleCommand.cancel(event), success: String(localized: "Olay iptal edildi."))
    }

    private func run(_ command: String, success: String) {
        guard !busy else { return }
        busy = true
        message = nil
        Task {
            do {
                try await PowerScheduleReader.apply(command)
                message = (success, .success)
            } catch AdministratorShell.Failure.cancelled {
                message = (String(localized: "Yönetici onayı verilmedi; değişiklik yapılmadı."), .neutral)
            } catch {
                message = (error.localizedDescription, .warning)
            }
            busy = false
            reload(adoptRepeating: true)
        }
    }
}

struct PowerScheduleView: View {
    @StateObject private var model = PowerScheduleModel()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Güç Zamanlaması",
                              subtitle: "Mac’in belirli saatlerde uyanmasını, açılmasını, uyumasını veya kapanmasını planla. Değişiklikler yönetici onayıyla macOS’a kaydedilir.",
                              icon: "calendar.badge.clock") {
                Button { model.reload(adoptRepeating: !model.hasChanges) } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(model.busy)
            }
            if let message = model.message { PocketMessage(message.text, tone: message.tone) }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    repeating
                    oneTime
                    notes
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !model.hasChanges && !model.busy { model.reload(adoptRepeating: true) }
        }
    }

    // MARK: Repeating

    private var repeating: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Tekrarlayan program", icon: "repeat") {
                Text(repeatingSummary)
            }
            eventRow(title: "Açılış", detail: "Mac uyuyorsa uyanır, kapalıysa açılır.", symbol: "sunrise.fill", tint: PocketTheme.power,
                     enabled: $model.onEnabled, kind: $model.onKind, kinds: PowerEventKind.onKinds, time: $model.onTime, days: $model.onDays)
            Divider()
            eventRow(title: "Kapanış", detail: "Belirlenen saatte uyku veya kapatma.", symbol: "moon.stars.fill", tint: PocketTheme.brandSecondary,
                     enabled: $model.offEnabled, kind: $model.offKind, kinds: PowerEventKind.offKinds, time: $model.offTime, days: $model.offDays)
            HStack {
                if model.hasChanges {
                    Label("Kaydedilmemiş değişiklik var", systemImage: "pencil.circle").font(.callout).foregroundStyle(.orange)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Geri Al") { model.reload(adoptRepeating: true) }.disabled(!model.hasChanges || model.busy)
                Button { model.applyRepeating() } label: { Label("Kaydet", systemImage: "lock") }
                    .buttonStyle(.pocketPrimary).disabled(!model.hasChanges || model.busy)
                    .help("Yönetici parolası istenir")
            }
        }
        .pocketCard()
    }

    private var repeatingSummary: String {
        let parts = [model.pendingOn, model.pendingOff].compactMap { $0 }.map { event in
            String(localized: "\(event.days.summary) \(event.timeText) \(event.kind.title.lowercased())")
        }
        return parts.isEmpty ? String(localized: "Program yok") : parts.joined(separator: " · ")
    }

    private func eventRow(title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String, tint: Color, enabled: Binding<Bool>,
                          kind: Binding<PowerEventKind>, kinds: [PowerEventKind], time: Binding<Date>, days: Binding<PowerWeekdays>) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: symbol, tint: tint, size: PocketIconSize.item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: enabled) { Text(title) }.pocketSwitch().labelsHidden()
            }
            if enabled.wrappedValue {
                HStack(spacing: PocketSpacing.m) {
                    Picker("Eylem", selection: kind) {
                        ForEach(kinds) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .fixedSize()
                        .pocketMenuPicker()
                    DatePicker("Saat", selection: time, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    Spacer(minLength: PocketSpacing.s)
                    DayChips(days: days)
                }
                .padding(.leading, 44)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: enabled.wrappedValue)
    }

    // MARK: One-time

    private var oneTime: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Tek seferlik olaylar", icon: "calendar") {
                Text(String(localized: "\(model.snapshot.scheduled.count) olay"))
            }
            if model.snapshot.scheduled.isEmpty {
                Text("Planlanmış tek seferlik olay yok.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.snapshot.scheduled) { event in
                        HStack(spacing: PocketSpacing.m) {
                            Image(systemName: event.kind.symbol).frame(width: 22).foregroundStyle(PocketTheme.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.kind.title).font(.headline)
                                Text(event.date.formatted(date: .complete, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.date.formatted(.relative(presentation: .named))).font(.callout).foregroundStyle(.secondary)
                            if !event.owner.isEmpty {
                                PocketStatusBadge(text: event.owner, tone: .neutral)
                            }
                            Button("İptal") { model.cancel(event) }.disabled(model.busy)
                        }
                        .padding(.vertical, PocketSpacing.s)
                        if event.id != model.snapshot.scheduled.last?.id { Divider() }
                    }
                }
            }
            Divider()
            HStack(spacing: PocketSpacing.m) {
                Text("Yeni olay").font(.headline)
                Picker("Eylem", selection: $model.oneTimeKind) {
                    ForEach(PowerEventKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden().fixedSize()
                    .pocketMenuPicker()
                DatePicker("Zaman", selection: $model.oneTimeDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().fixedSize()
                Spacer()
                Button { model.addOneTime() } label: { Label("Ekle", systemImage: "plus") }
                    .disabled(model.busy)
                    .help("Yönetici parolası istenir")
            }
        }
        .pocketCard()
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            Label("Kapatma sırasında kaydedilmemiş belgeler varsa macOS uyarı gösterir ve uygulamalar kapanmayı erteleyebilir.", systemImage: "doc.badge.ellipsis")
            Label("“Aç”, Mac tamamen kapalıyken çalışır; masaüstü Mac’ler prize takılı olmalıdır. Dizüstülerde kapak kapalıyken uyandırma ekranı açmaz.", systemImage: "powerplug")
            Label("macOS yalnız bir açılış ve bir kapanış tekrarı saklar; tek seferlik olayların sayısı sınırsızdır.", systemImage: "info.circle")
        }
        .font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, PocketSpacing.xs)
    }
}

private struct DayChips: View {
    @Binding var days: PowerWeekdays

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PowerWeekdays.ordered, id: \.rawValue) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(day.shortTitle).font(.caption.weight(.semibold))
                        .frame(width: 34, height: 24)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? AnyShapeStyle(PocketTheme.brand) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Menu {
                Button("Her gün") { days = .everyDay }
                Button("Hafta içi") { days = .weekdays }
                Button("Hafta sonu") { days = .weekend }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Gün hazır ayarları")
                .help("Gün hazır ayarları")
                .menuStyle(.borderlessButton).fixedSize()
        }
    }
}
