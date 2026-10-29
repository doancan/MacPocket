import AppKit
import MacPocketCore
import SwiftUI
import SystemConfiguration

struct OverviewView: View {
    @ObservedObject var model: PocketModel
    @ObservedObject var files: FileWorkspaceModel
    @ObservedObject var applications: ApplicationWorkspaceModel
    let navigation: PocketNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PocketPageHeading(title: "Genel Bakış", subtitle: "Mac’inin durumu, bakım işlemleri ve günlük araçların.", icon: "square.grid.2x2")
                deviceOverview
                HStack(alignment: .top, spacing: 16) {
                    storageOverview
                    applicationsOverview
                }
                HStack(alignment: .top, spacing: 16) {
                    powerOverview
                    toolsOverview
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task { if !applications.loaded { await applications.load() } }
    }

    private var deviceOverview: some View {
        HStack(spacing: 28) {
            Image(systemName: model.system?.power.batteryPresent == true ? "laptopcomputer" : "desktopcomputer")
                .font(.system(size: 62, weight: .ultraLight)).foregroundStyle(PocketTheme.accent)
                .frame(width: 110, height: 110)
                .background(PocketTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 9) {
                Text(SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac’in")
                    .font(.system(size: 25, weight: .semibold)).lineLimit(2)
                Text(model.system.map { "\($0.logicalCPUCount) mantıksal çekirdek · \(pocketBytes($0.physicalMemoryBytes)) RAM" } ?? "Donanım bilgisi okunuyor…")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Label(model.system?.thermalState == "nominal" ? "Termal durum normal" : (model.system?.thermalState ?? "Örnek bekleniyor"), systemImage: "thermometer.medium")
                    Label("CPU \(model.cpuLabel)", systemImage: "cpu")
                }.font(.callout).foregroundStyle(.secondary)
                Button("Sistem İzlemeyi Aç") { navigation.select(.performance) }.controlSize(.small)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Text("BU MAC").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(ProcessInfo.processInfo.operatingSystemVersionString).font(.callout)
                if let updated = model.lastUpdate {
                    Text("Son ölçüm \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private var storageOverview: some View {
        OverviewPanel(title: "Depolama", icon: "internaldrive", action: "Disk Analizini Aç", perform: { navigation.select(.storage) }) {
            if let volume = model.system?.volumes.first {
                Text("\(pocketBytes(UInt64(max(0, volume.availableBytes)))) kullanılabilir").font(.title3.weight(.semibold))
                ProgressView(value: Double(max(0, volume.totalBytes - volume.availableBytes)), total: Double(max(1, volume.totalBytes)))
                    .tint(PocketTheme.accent)
                Text("\(volume.name) · \(pocketBytes(UInt64(max(0, volume.totalBytes)))) toplam").font(.caption).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 3)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temizlik").font(.headline)
                    Text(files.report.map { "\($0.fileCount.formatted()) dosya incelendi" } ?? "Alan kaplayan öğeleri tarayarak başla.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("İncele") { navigation.select(.cleanup) }
            }
        }
    }
    private var applicationsOverview: some View {
        OverviewPanel(title: "Uygulamalar", icon: "app.badge", action: "Uygulamaları Yönet", perform: { navigation.select(.applications) }) {
            Text(applications.loaded ? "\(applications.applications.count) kurulu uygulama" : "Uygulamalar inceleniyor…")
                .font(.title3.weight(.semibold))
            Text("Sürümleri ve kurulum kanallarını gör. Kaldırmadan önce ilişkili dosyaları incele.")
                .font(.callout).foregroundStyle(.secondary)
            Divider().padding(.vertical, 3)
            HStack {
                Text(applications.updatesCheckedAt == nil ? "Güncellemeler henüz kontrol edilmedi." : "\(applications.updates.count) Homebrew güncellemesi")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Güncellemeler") { applications.showUpdates = true; navigation.select(.applications) }
            }
        }
    }
    private var powerOverview: some View {
        OverviewPanel(title: "Güç", icon: "bolt", action: "Güç Merkezini Aç", perform: { navigation.select(.power) }) {
            Text(model.system?.power.batteryPresent == true
                 ? (model.system?.power.chargePercent.map { String(format: "Pil %.0f%%", $0) } ?? "Pil seviyesi okunuyor")
                 : "Prizden çalışıyor").font(.title3.weight(.semibold))
            Text(model.system?.power.batteryPresent == true ? "Pil, termal durum ve uyku yönetimi." : "Bu Mac’te dahili pil yok. Enerji ve uyku araçları kullanılabilir.")
                .font(.callout).foregroundStyle(.secondary)
            Label(model.awakeSession?.active == true ? "Uyanık tutma etkin" : "Otomatik uyku normal", systemImage: "moon.zzz")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private var toolsOverview: some View {
        OverviewPanel(title: "Araç Kutusu", icon: "wrench.and.screwdriver", action: "Tüm Araçları Aç", perform: { navigation.select(.tools) }) {
            VStack(alignment: .leading, spacing: 10) {
                Button { navigation.open(.taskManager) } label: { Label("Görev Yöneticisi", systemImage: "list.bullet.rectangle") }
                Button { navigation.open(.diagnostics) } label: { Label("Sistem Raporları", systemImage: "terminal") }
                Button { navigation.select(.storage); model.storage.scope = .duplicates } label: { Label("Yinelenen Dosyalar", systemImage: "doc.on.doc") }
            }.buttonStyle(.borderless)
        }
    }
}

private struct OverviewPanel<Content: View>: View {
    let title: String
    let icon: String
    let action: String
    let perform: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.headline)
            content()
            Spacer(minLength: 0)
            Button(action, action: perform).controlSize(.small)
        }.padding(22).frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}
