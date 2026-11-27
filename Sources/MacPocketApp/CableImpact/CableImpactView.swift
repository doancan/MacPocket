import MacPocketCore
import SwiftUI

struct CableImpactView: View {
    @StateObject private var model: CableImpactModel
    @State private var pairingExpanded = false
    private let observesHardware: Bool
    init(model: CableImpactModel = .init(), observesHardware: Bool = true) {
        _model = StateObject(wrappedValue: model)
        self.observesHardware = observesHardware
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Kablo Etki Haritası", subtitle: "Bu kabloyu çekersem ne olur? Bağlı aygıtları ve açık işleri birlikte gör.", icon: "cable.connector") {
                HStack {
                    if model.scanning { Button("Vazgeç", action: model.cancel) }
                    Button { Task { await model.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                        .disabled(model.loading)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if let failure = model.failure { PocketMessage(failure, tone: .warning) }
                    if let notice = model.mappingNotice { PocketMessage(notice, tone: .warning) }
                    if model.loading { PocketProgressRow(message: "Bağlantılar ve kaynaklar okunuyor…") }
                    if let inventory = model.inventory, !inventory.connections.isEmpty {
                        connectionPicker(inventory)
                        if let selection = model.selection {
                            impact(selection)
                            pairing(inventory, selection: selection)
                        }
                        coverage(inventory)
                    } else if model.loaded && !model.loading && model.failure == nil {
                        ContentUnavailableView("Çıkarılabilir bağlantı bulunamadı", systemImage: "cable.connector.slash",
                                               description: Text("macOS çıkarılabilir USB veya Thunderbolt aygıtı bildirmedi. Bir aygıt bağlayıp listeyi yenile."))
                            .frame(maxWidth: .infinity, minHeight: 180)
                        if let inventory = model.inventory { coverage(inventory) }
                    }
                }.padding(.bottom, PocketSpacing.l)
            }
        }.pocketPage()
        .task { if observesHardware { await model.run() } }
        .onDisappear { model.stop() }
        .onChange(of: model.selectedID) { pairingExpanded = model.affected.isEmpty }
    }

    private func connectionPicker(_ inventory: CableInventory) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Picker("Bağlantı / aygıt", selection: Binding(get: { model.selectedID }, set: model.select)) {
                Text("Bağlantı seç…").tag(nil as String?)
                ForEach(inventory.connections) { connection in Text(connection.name).tag(Optional(connection.id)) }
            }.pocketMenuPicker().disabled(model.loading)
            if model.selection?.groupedByContainer == true {
                Text("Bu aygıtın ortak donanım kimliği bildiren USB işlevleri birlikte değerlendiriliyor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Donanım okuması: \(inventory.capturedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }

    private func impact(_ selection: CableConnection) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                Image(systemName: selection.isThunderbolt ? "bolt.horizontal" : "cable.connector")
                    .font(.title2).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.name).font(.headline).textSelection(.enabled)
                    Text("Bu bağlantıdan etkilenebilecek kaynaklar").foregroundStyle(.secondary)
                }
            }
            if model.scanning { PocketProgressRow(message: "Açık dosyalar ve ağ oturumları denetleniyor…") }
            if let report = model.report {
                Text("Kullanım okuması: \(report.capturedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.affected.isEmpty {
                Text(CableEndpoint.Kind.allCases.compactMap { kind -> String? in
                    let count = model.affected.filter { $0.endpoint.kind == kind }.count
                    return count > 0 ? String(localized: "\(kind.localizedTitle): \(count)") : nil
                }.joined(separator: " · ")).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            if model.affected.isEmpty {
                Text("Bu aygıtın altında eşleştirilebilen kaynak bulunamadı. Bu, kabloyu çekmenin etkisiz olduğu anlamına gelmez.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(CableEndpoint.Kind.allCases, id: \.self) { kind in
                let rows = model.affected.filter { $0.endpoint.kind == kind }
                if !rows.isEmpty {
                    Divider()
                    Text(kind.localizedTitle).font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(rows) { item in endpoint(item) }
                }
            }
            if model.affected.contains(where: { $0.endpoint.kind == .storage }) {
                Button("USB Çıkarma Yöneticisini Aç") { NotificationCenter.default.post(name: .pocketOpenTool, object: "usb-eject") }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }

    private func endpoint(_ item: CableAffectedEndpoint) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .top, spacing: PocketSpacing.m) {
                Image(systemName: item.endpoint.kind.symbol).frame(width: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.endpoint.name).font(.system(.body, weight: .semibold)).textSelection(.enabled)
                    Label(item.evidence.localizedTitle, systemImage: item.evidence == .registry ? "link" : "person.crop.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    if !item.endpoint.detail.isEmpty { Text(item.endpoint.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Text(consequence(item.endpoint)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if item.endpoint.isDefault { Label("Varsayılan", systemImage: "star") }
                        if item.endpoint.active { Label("Etkin / bağlı", systemImage: "circle.fill") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            if let report = model.report {
                if let users = report.diskUsers[item.id] {
                    Text("Açık dosya kullanan süreç sayısı: \(users.count)").font(.caption)
                    ForEach(users) { user in
                        DisclosureGroup {
                            ForEach(Array(user.files.prefix(10).enumerated()), id: \.offset) { _, file in
                                Text(file).font(.caption).textSelection(.enabled)
                            }
                            if user.files.count > 10 { Text("Listede ilk 10 dosya gösteriliyor.").font(.caption).foregroundStyle(.secondary) }
                        } label: { Text("\(user.command) · PID \(String(user.pid)) · Dosya sayısı: \(user.files.count)").font(.caption) }
                    }
                }
                if let sessions = report.sessions[item.id] {
                    Text("Yerel adresi eşleşen TCP oturumu sayısı: \(sessions.count)").font(.caption)
                    ForEach(sessions.prefix(20)) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(session.command) · PID \(String(session.pid))").font(.caption.weight(.semibold))
                                if session.isSSH { Label("SSH oturumu", systemImage: "terminal").font(.caption) }
                            }
                            Text("\(session.local) → \(session.remote)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    if sessions.count > 20 { Text("Listede ilk 20 TCP oturumu gösteriliyor.").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding(.vertical, PocketSpacing.xs)
    }

    private func pairing(_ inventory: CableInventory, selection: CableConnection) -> some View {
        DisclosureGroup(isExpanded: $pairingExpanded) {
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                Text("Yalnız fiziksel olarak aynı kabloya bağlı olduğunu bildiğin öğeleri seç. Bunlar otomatik doğrulama olarak sunulmaz. Eşleştirmeler bu ekranın oturumunda tutulur.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                let others = inventory.connections.filter { $0.id != selection.id }
                if !others.isEmpty {
                    Text("Aynı kablonun diğer aygıtları").font(.subheadline.weight(.semibold))
                    ForEach(others) { connection in
                        Toggle(connection.name, isOn: Binding(get: { model.additionalConnections[selection.id]?.contains(connection.id) == true },
                                                             set: { model.pairConnection(connection.id, enabled: $0) }))
                    }
                }
                if !model.unassigned.isEmpty {
                    Text("Bağı otomatik doğrulanamayan kaynaklar").font(.subheadline.weight(.semibold))
                    ForEach(model.unassigned) { resource in
                        Toggle(isOn: Binding(get: { model.manualEndpoints[selection.id]?.contains(resource.id) == true },
                                             set: { model.pairEndpoint(resource.id, enabled: $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(resource.name, systemImage: resource.kind.symbol)
                                if !resource.detail.isEmpty { Text(resource.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.accessibilityLabel("\(resource.name): aynı kabloya bağlı")
                    }
                }
                if others.isEmpty && model.unassigned.isEmpty { Text("Eşleştirilecek başka kaynak yok.").foregroundStyle(.secondary) }
            }.toggleStyle(.checkbox).padding(.top, PocketSpacing.m).disabled(model.loading)
        } label: { Text("Bağı belirsiz kaynaklar ve eşleştirme").font(.headline) }
        .frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }

    private func coverage(_ inventory: CableInventory) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            ForEach(Array((model.report?.issues ?? inventory.issues).enumerated()), id: \.offset) { _, issue in PocketMessage(issue, tone: .warning) }
            Text("Harita salt okunur; aygıt çıkarmaz, süreç kapatmaz veya ağı değiştirmez. Donanım değişiklikleri ekran açıkken izlenir; kullanım bilgilerini Yenile ile güncelle.")
            Text("Açık dosyalar ve TCP oturumları bu kullanıcıya görünür kapsamla sınırlıdır. VPN, köprü ve çoklu yol bağlantıları tam eşleştirilemeyebilir. Yazma önbelleği, güç dağıtımı ve bağlı tüm işlerin sürekliliği doğrulanmaz.")
            Text("TCP oturumları yerel IP adresine göre eşleştirilir; gerçek paket güzergâhı ölçülmez.")
        }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func consequence(_ endpoint: CableEndpoint) -> String {
        switch endpoint.kind {
        case .storage: String(localized: "Dosyalara erişim kesilebilir. Çıkarmadan önce kaydet ve diski güvenle çıkar.")
        case .network:
            endpoint.isDefault ? String(localized: "Varsayılan ağ yolu burada. Başka bir ağa geçiş garanti değildir.") :
                String(localized: "Bu arayüzdeki ağ oturumları kesilebilir.")
        case .display: String(localized: "Ekran kaybolabilir; pencereler diğer ekranlara taşınabilir.")
        case .audio: String(localized: "Ses veya mikrofon bağlantısı kesilebilir. Sonraki aygıtı macOS belirler.")
        case .usb: String(localized: "Kablo çıkarılırsa bu aygıta erişim etkilenebilir.")
        }
    }
}
