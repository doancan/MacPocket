import MacPocketCore
import SwiftUI

/// Tools → Bluetooth Pilleri: battery rings for connected accessories and the low-battery alert.
struct BluetoothBatteryView: View {
    @ObservedObject private var service = BluetoothBatteryService.shared
    @ObservedObject private var menuBar = MenuBarSettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Bluetooth Pilleri",
                              subtitle: "Klavye, trackpad, fare ve kulaklıkların pil durumu; azalınca bildirim.",
                              icon: "battery.75percent") {
                Button { Task { await service.refresh(forceProfile: true) } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(service.loading)
            }
            if service.logitechNeedsPermission {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Logitech aygıtlarının pilini okumak için Giriş İzleme izni gerekir. MacPocket yalnız pil sorusu gönderir; tuş ya da hareket kaydetmez.", tone: .warning)
                    Button("İzin ver…") { service.requestLogitechAccess() }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if service.loading { PocketProgressRow(message: "Bluetooth aygıtları okunuyor…") }
                    if service.devices.isEmpty, !service.loading {
                        ContentUnavailableView("Bağlı Bluetooth aygıtı yok",
                                               systemImage: "dot.radiowaves.left.and.right",
                                               description: Text("Bir klavye, fare ya da kulaklık bağlanınca burada görünür."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .pocketCard()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: PocketSpacing.m)], spacing: PocketSpacing.m) {
                            ForEach(service.devices) { device in BatteryDeviceCard(device: device, threshold: service.settings.threshold) }
                        }
                    }
                    alertsCard
                    if let updated = service.updatedAt {
                        Text("Son okuma \(updated.formatted(date: .omitted, time: .shortened)) · her dakika yenilenir")
                            .font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .task { await service.refresh() }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Toggle(isOn: $service.settings.lowBatteryAlerts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pil azalınca bildir").font(.headline)
                    Text("Her aygıt için bir kez bildirilir; eşiğin 10 puan üstüne şarj edilince yeniden kurulur.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Picker("Eşik", selection: $service.settings.threshold) {
                ForEach([10, 15, 20, 30], id: \.self) { value in Text("%\(value)").tag(value) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(!service.settings.lowBatteryAlerts)
            Divider().padding(.vertical, PocketSpacing.xs)
            HStack(spacing: PocketSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menü çubuğu").font(.headline)
                    Text(menuBar.preferences.visible && menuBar.preferences.enabled.contains(.bluetooth)
                         ? "Bluetooth pilleri modülü menü çubuğunda en düşük pili gösteriyor."
                         : "Menü çubuğunda göstermek için İstatistik Çubuğu sayfasında Bluetooth pilleri modülünü aç.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PocketSpacing.s)
                Button("İstatistik Çubuğu…") { PocketApplicationState.shared.model.navigation.openMenuBar(module: .bluetooth) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

private struct BatteryDeviceCard: View {
    let device: BluetoothBatteryDevice
    let threshold: Int

    private func color(_ level: Int) -> Color {
        level <= threshold ? .red : level <= threshold + 15 ? .orange : .green
    }

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                if let level = device.levels.lowest {
                    Circle().trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(color(level).gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: device.kind.symbol).font(.system(size: 18, weight: .medium))
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: device.name).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if device.levelUnavailable {
                    Text("Pil bilgisi alınamıyor").font(.subheadline).foregroundStyle(.secondary)
                } else if device.levels.left != nil || device.levels.right != nil {
                    HStack(spacing: PocketSpacing.s) {
                        part("Sol", device.levels.left)
                        part("Sağ", device.levels.right)
                        part("Kutu", device.levels.batteryCase)
                    }
                } else if let level = device.levels.lowest {
                    HStack(spacing: 4) {
                        Text("%\(level)").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color(level))
                        if device.charging { Image(systemName: "bolt.fill").foregroundStyle(.green).help("Şarj oluyor") }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .pocketCard(padding: PocketSpacing.m)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func part(_ title: LocalizedStringKey, _ level: Int?) -> some View {
        if let level {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text("%\(level)").font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(color(level))
            }
        }
    }
}
