import AppKit
import MacPocketCore
import SwiftUI

enum StatusMetric: String, CaseIterable, Identifiable {
    case cpu, memory, disk, battery, power
    var id: String { rawValue }
    var title: String { switch self { case .cpu: "CPU"; case .memory: "RAM"; case .disk: "Disk"; case .battery: "Pil"; case .power: "Güç" } }
    var symbol: String { switch self { case .cpu: "cpu"; case .memory: "memorychip"; case .disk: "internaldrive"; case .battery: "battery.100percent"; case .power: "bolt" } }
    var key: String { self == .cpu ? "MacPocket.menuBarCPU" : "MacPocket.bar.\(rawValue)" }
    func enabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? (self == .cpu)
    }
    static func ordered(_ defaults: UserDefaults = .standard) -> [Self] {
        let saved = (defaults.string(forKey: "MacPocket.bar.order") ?? "").split(separator: ",").compactMap { Self(rawValue: String($0)) }
        var seen = Set<Self>()
        return (saved + allCases).filter { seen.insert($0).inserted }
    }
}

struct StatusMetricValue {
    let text: String
    let detail: String
    let fraction: Double?
}

@MainActor
func statusMetricValue(_ metric: StatusMetric, snapshot: SystemSnapshot?, defaults: UserDefaults = .standard) -> StatusMetricValue {
    guard let s = snapshot else { return .init(text: "—", detail: "İlk ölçüm bekleniyor", fraction: nil) }
    func percent(_ value: Double) -> String { String(format: defaults.bool(forKey: "MacPocket.bar.decimals") ? "%.1f%%" : "%.0f%%", value) }
    func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = defaults.string(forKey: "MacPocket.bar.units") == "decimal" ? .decimal : .binary
        return formatter.string(fromByteCount: Int64(clamping: value))
    }
    switch metric {
    case .cpu:
        guard let user = s.cpuUserPercent, let system = s.cpuSystemPercent else { return .init(text: "—", detail: "CPU intervali bekleniyor", fraction: nil) }
        return .init(text: percent(user + system), detail: "CPU toplam · Kullanıcı \(percent(user)) · Sistem \(percent(system))", fraction: (user + system) / 100)
    case .memory:
        let value: UInt64
        let name: String
        switch defaults.string(forKey: "MacPocket.bar.memoryValue") ?? "free" {
        case "wired": value = s.wiredMemoryBytes; name = "Wired RAM"
        case "compressed": value = s.compressedMemoryBytes; name = "Sıkıştırıcının fiziksel RAM alanı"
        case "physical": value = s.physicalMemoryBytes; name = "Toplam fiziksel RAM"
        default: value = s.freeMemoryBytes; name = "Ham boş RAM (kullanılabilir bellek değildir)"
        }
        let fraction = s.physicalMemoryBytes > 0 ? Double(value) / Double(s.physicalMemoryBytes) : nil
        return .init(text: defaults.bool(forKey: "MacPocket.bar.memoryPercent") ? fraction.map { percent($0 * 100) } ?? "—" : bytes(value), detail: "\(name): \(bytes(value)) / \(bytes(s.physicalMemoryBytes))", fraction: fraction)
    case .disk:
        let path = defaults.string(forKey: "MacPocket.bar.volume") ?? ""
        guard let volume = (path.isEmpty ? s.volumes.first : s.volumes.first(where: { $0.path == path })) else { return .init(text: "—", detail: path.isEmpty ? "Disk ölçümü yok" : "Seçili disk bağlı değil: \(path)", fraction: nil) }
        let free = max(0, volume.availableBytes), total = max(1, volume.totalBytes)
        let used = max(0, total - free)
        let fraction = min(1, Double(used) / Double(total))
        return .init(text: defaults.bool(forKey: "MacPocket.bar.diskPercent") ? percent(fraction * 100) : bytes(UInt64(free)), detail: "\(volume.name) · \(bytes(UInt64(free))) boş / \(bytes(UInt64(total))) toplam · Gösterge: doluluk", fraction: fraction)
    case .battery:
        return .init(text: s.power.chargePercent.map(percent) ?? "—", detail: "Pil · \(s.power.isCharging == true ? "Şarj oluyor" : "Şarj olmuyor")", fraction: s.power.chargePercent.map { $0 / 100 })
    case .power:
        let source = s.power.source == "AC Power" ? "AC" : s.power.source == "Battery Power" ? "Pil" : s.power.source
        return .init(text: source + (s.power.lowPowerMode ? " ↓" : ""), detail: "\(s.power.source) · \(s.power.lowPowerMode ? "Düşük güç" : "Standart güç") · Termal: \(s.thermalState)", fraction: nil)
    }
}

struct StatusBarPreferencesView: View {
    @ObservedObject var model: PocketModel
    @AppStorage("MacPocket.showMenuBar") private var visible = true
    @AppStorage("MacPocket.bar.layout") private var layout = "combined"
    @AppStorage("MacPocket.bar.style") private var style = "text"
    @AppStorage("MacPocket.bar.labels") private var labels = true
    @AppStorage("MacPocket.bar.icons") private var icons = true
    @AppStorage("MacPocket.bar.compact") private var compact = false
    @AppStorage("MacPocket.bar.decimals") private var decimals = false
    @AppStorage("MacPocket.bar.units") private var units = "binary"
    @AppStorage("MacPocket.bar.memoryValue") private var memory = "free"
    @AppStorage("MacPocket.bar.memoryPercent") private var memoryPercent = false
    @AppStorage("MacPocket.bar.diskPercent") private var diskPercent = false
    @AppStorage("MacPocket.bar.volume") private var volume = ""
    @AppStorage("MacPocket.bar.fontSize") private var fontSize = 12.0
    @AppStorage("MacPocket.bar.order") private var order = "cpu,memory,disk,battery,power"
    var body: some View {
        Form {
            Section("Yerleşim") {
                Toggle("Menü çubuğunda göster", isOn: $visible)
                Picker("Göstergeler", selection: $layout) {
                    Text("Tek birleşik grup").tag("combined")
                    Text("Ayrı ayrı").tag("separate")
                }.pickerStyle(.segmented)
                Text("Ayrı göstergeler macOS menü çubuğunda ⌘ ile sürüklenebilir. Pil göstergesi yalnız pil bulunan cihazlarda görünür.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(StatusMetric.ordered()) { metric in
                    StatusMetricToggle(metric: metric, order: $order)
                }
                Text("Hiç gösterge seçilmezse MacPocket simgesi korunur. Sığmayan göstergeleri macOS ekran alanına göre gizleyebilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Gösterim") {
                Picker("Stil", selection: $style) {
                    Text("Değer").tag("text"); Text("Mini gösterge + değer").tag("gauge"); Text("Mini gösterge").tag("gaugeOnly")
                }
                Toggle("Etiketleri göster", isOn: $labels)
                Toggle("Simgeleri göster", isOn: $icons)
                Toggle("Sıkı aralık", isOn: $compact)
                Toggle("Yüzdelerde ondalık basamak", isOn: $decimals)
                LabeledContent("Yazı boyutu") { Slider(value: $fontSize, in: 10...14, step: 1).frame(width: 130); Text("\(Int(fontSize)) pt").monospacedDigit() }
                Picker("Boyut birimi", selection: $units) { Text("İkili (1024)").tag("binary"); Text("Ondalık (1000)").tag("decimal") }
            }
            Section("RAM ve disk") {
                Picker("RAM değeri", selection: $memory) {
                    Text("Ham boş").tag("free"); Text("Wired").tag("wired"); Text("Sıkıştırıcı alanı").tag("compressed"); Text("Fiziksel toplam").tag("physical")
                }
                Toggle("RAM’i yüzde olarak göster", isOn: $memoryPercent)
                Text("Ham boş RAM, Activity Monitor’daki kullanılabilir bellek değildir. Yüzde seçilen alanın fiziksel RAM’e oranıdır.").font(.caption).foregroundStyle(.secondary)
                Picker("Disk", selection: $volume) {
                    Text("Otomatik").tag("")
                    if !volume.isEmpty, !(model.system?.volumes.contains { $0.path == volume } ?? false) { Text(volume + " (bağlı değil)").tag(volume) }
                    ForEach(model.system?.volumes ?? [], id: \.path) { item in Text(item.name).tag(item.path) }
                }
                Toggle("Disk boş alanı yerine doluluk yüzdesi", isOn: $diskPercent)
            }
            Section("Örnekleme") {
                Picker("Yenileme", selection: $model.refreshSeconds) {
                    Text("1 saniye").tag(1.0); Text("2 saniye").tag(2.0); Text("5 saniye").tag(5.0); Text("10 saniye").tag(10.0)
                }
                Text("Göstergeler ve ana pencere aynı gerçek ölçümleri kullanır. İzleme duraklatıldığında son değer korunur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct StatusMetricToggle: View {
    let metric: StatusMetric
    @Binding var order: String
    @AppStorage private var enabled: Bool
    init(metric: StatusMetric, order: Binding<String>) {
        self.metric = metric; _order = order
        _enabled = AppStorage(wrappedValue: metric == .cpu, metric.key)
    }
    var body: some View {
        HStack {
            Toggle(isOn: $enabled) { Label(metric.title, systemImage: metric.symbol) }
            Spacer()
            Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Öne al")
            Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(index == StatusMetric.allCases.count - 1).help("Arkaya al")
        }.controlSize(.small)
    }
    private var index: Int { StatusMetric.ordered().firstIndex(of: metric) ?? 0 }
    private func move(_ delta: Int) {
        var list = StatusMetric.ordered()
        let target = index + delta
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        order = list.map(\.rawValue).joined(separator: ",")
    }
}
