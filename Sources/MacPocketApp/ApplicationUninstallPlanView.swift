import AppKit
import MacPocketCore
import SwiftUI

struct UninstallPlanView: View {
    let plan: UninstallPlan
    @ObservedObject var model: ApplicationWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @StateObject private var preparation: UninstallPreparationModel
    @State private var confirm = false
    @State private var forceConfirmation = false
    @State private var forceConsent = Set<ProcessIdentity>()
    @State private var confirmedSelection = Set<String>()
    @State private var pending = false
    @State private var operationError: String?
    @State private var work: Task<Void, Never>?
    @State private var processesExpanded = false

    private var working: Bool { pending || model.busy || model.updatingToken != nil }
    private var includesApplication: Bool { selected.contains(plan.application.id) }
    private var removesHomebrewApplication: Bool { model.cask(for: plan.application) != nil && includesApplication }
    private var userDataSelected: Bool { plan.candidates.contains { $0.containsUserData && selected.contains($0.id) } }
    private var error: String? { preparation.failure ?? operationError }
    private var temporaryItems: [UninstallCandidate] { plan.candidates.filter { !$0.request.applicationBundle && !$0.containsUserData } }
    private var userDataItems: [UninstallCandidate] { plan.candidates.filter(\.containsUserData) }

    init(plan: UninstallPlan, model: ApplicationWorkspaceModel, preparation: UninstallPreparationModel? = nil) {
        self.plan = plan; self.model = model
        _selected = State(initialValue: [plan.application.id])
        _preparation = StateObject(wrappedValue: preparation ?? model.uninstallPreparation(for: plan.application))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PocketSpacing.xl) {
                        processStatus.id("uninstall-status")
                        candidateGroup(title: "Uygulama", subtitle: "Uygulama paketini kaldır.", items: plan.candidates.filter { $0.request.applicationBundle }, bulkSelection: false)
                        if !temporaryItems.isEmpty {
                            candidateGroup(title: "Önbellek ve günlükler", subtitle: "Bu uygulamaya ait geçici ve tanılama dosyaları.", items: temporaryItems)
                        }
                        if !userDataItems.isEmpty {
                            candidateGroup(title: "Kullanıcı verileri", subtitle: "Tercihler ve kişisel içerik. Bu öğeler varsayılan olarak seçilmez.", items: userDataItems)
                        }
                        DisclosureGroup("Kaldırma kapsamı") {
                            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                                Text("Yalnız seçilen uygulama paketine ait süreçler kapatılır. Paylaşılan servisler ve paket dışındaki yardımcılar otomatik durdurulmaz.")
                                Text("Seçilen klasörler içerikleriyle birlikte taşınır. Paylaşılan üretici ve App Group klasörleri plana eklenmez.")
                                if removesHomebrewApplication {
                                    Text("Homebrew, paketin kendi kaldırma yönergelerini de çalıştırır; bu yönergeler ek servisleri durdurabilir.")
                                }
                            }.font(.caption).foregroundStyle(.secondary).padding(.top, PocketSpacing.s)
                        }.font(.callout).foregroundStyle(.secondary)
                    }.padding(PocketSpacing.xl)
                }
                .onChange(of: error) {
                    if error != nil { processesExpanded = true; proxy.scrollTo("uninstall-status", anchor: .top) }
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1000, minHeight: 560, idealHeight: 680, maxHeight: 850)
        .interactiveDismissDisabled(working)
        .task {
            while !Task.isCancelled {
                if !pending { await preparation.refresh() }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onAppear { processesExpanded = error != nil }
        .onDisappear { work?.cancel(); preparation.cancel() }
        .alert(forceConfirmation ? String(localized: "Zorla kapatıp kaldırmak istiyor musun?") : String(localized: "Seçilen öğeler kaldırılsın mı?"), isPresented: $confirm) {
            Button("Vazgeç", role: .cancel) {}
            Button(confirmationAction, role: .destructive, action: execute)
        } message: { Text(confirmationMessage) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            PocketAppIcon(url: plan.application.url, size: 48)
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Text("Kaldırma Planı").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(plan.application.name).font(.title2.weight(.semibold)).lineLimit(2)
                HStack(spacing: PocketSpacing.s) {
                    if plan.application.version != "—" { Text("Sürüm \(plan.application.version)") }
                    Text(model.cask(for: plan.application) == nil ? plan.application.channel.localizedTitle : "Homebrew")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: PocketSpacing.m)
            if pending && !model.busy {
                Button("Beklemeyi Durdur") { work?.cancel(); preparation.cancel() }
            } else {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                    .buttonStyle(.borderless).accessibilityLabel("Kapat").help("Kapat").disabled(working)
            }
        }.padding(PocketSpacing.xl)
    }

    private var processStatus: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(alignment: .center, spacing: PocketSpacing.s) {
                if pending || !preparation.checked && error == nil { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: preparation.processes.isEmpty ? "checkmark.circle" : "circle.fill")
                        .foregroundStyle(preparation.processes.isEmpty ? Color.secondary : .orange).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if pending { Text("Kapatma ve kaldırma işlemi sürüyor…").font(.callout.weight(.medium)) }
                    else if !preparation.checked { Text("Süreçler denetleniyor…").font(.callout) }
                    else if preparation.processes.isEmpty {
                        Text("Çalışan süreç bulunmadı").font(.callout.weight(.medium))
                        Text("Kaldırma başlamadan önce yeniden kontrol edilir.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Önce uygulama kapatılacak").font(.callout.weight(.medium))
                        Text("Çalışan süreç sayısı: \(preparation.processes.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { Task { await preparation.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                    .buttonStyle(.borderless).help("Durumu Yenile").accessibilityLabel("Durumu Yenile").disabled(working)
            }
            if !preparation.processes.isEmpty {
                DisclosureGroup("Çalışan süreçler", isExpanded: $processesExpanded) {
                    VStack(spacing: PocketSpacing.s) {
                        ForEach(preparation.processes) { process in
                            HStack(spacing: PocketSpacing.s) {
                                Image(systemName: process.isMainApplication ? "app" : "gearshape.2").frame(width: 18).accessibilityHidden(true)
                                Text(process.name).lineLimit(1)
                                Spacer()
                                Text("PID \(String(process.pid))").monospacedDigit().foregroundStyle(.secondary)
                                if !process.canStop { Text("Elle kapatılmalı").foregroundStyle(.secondary) }
                            }.font(.caption).textSelection(.enabled)
                        }
                    }.padding(.top, PocketSpacing.s)
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let error { PocketMessage(error, tone: .warning) }
            if preparation.canOfferForce {
                Button("Zorla Kapat ve Kaldır…", role: .destructive) { askConfirmation(force: true) }
                    .buttonStyle(.borderless).disabled(working || selected.isEmpty)
            }
        }.padding(PocketSpacing.m)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: PocketRadius.medium))
    }

    private func candidateGroup(title: LocalizedStringKey, subtitle: LocalizedStringKey,
                                items: [UninstallCandidate], bulkSelection: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if bulkSelection {
                    Button(items.allSatisfy { selected.contains($0.id) } ? String(localized: "Seçimi Kaldır") : String(localized: "Tümünü Seç")) {
                        let ids = Set(items.map(\.id))
                        if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
                    }.font(.caption).buttonStyle(.borderless).disabled(working)
                }
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 { Divider().padding(.leading, 44) }
                    HStack(spacing: PocketSpacing.m) {
                        Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { value in
                            if value { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.request.applicationBundle ? plan.application.name : candidate.title).font(.callout.weight(.medium))
                                Text(shortPath(candidate.request.url)).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle).help(candidate.request.url.path)
                            }
                        }.toggleStyle(.checkbox).disabled(working)
                        Spacer(minLength: 0)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([candidate.request.url]) } label: {
                            Image(systemName: "folder").frame(width: 28, height: 28)
                        }.buttonStyle(.borderless).help("Finder’da Göster")
                            .accessibilityLabel("\(candidate.title): Finder’da Göster").disabled(working)
                    }.padding(.horizontal, PocketSpacing.m).padding(.vertical, 10)
                }
            }.pocketCard(padding: 0, radius: PocketRadius.medium)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: PocketSpacing.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Seçilen öğe sayısı: \(selected.count)").font(.callout.weight(.semibold)).monospacedDigit()
                Text(selectionSummary).font(.caption).foregroundStyle(userDataSelected ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
            Button(removalTitle, role: .destructive) { askConfirmation(force: false) }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(selected.isEmpty || working || !preparation.checked)
        }.controlSize(.large).padding(.horizontal, PocketSpacing.xl).padding(.vertical, PocketSpacing.l)
    }
    private var selectionSummary: String {
        if !includesApplication {
            return userDataSelected ? String(localized: "Uygulama kalacak; seçili kullanıcı verileri kaldırılacak.") : String(localized: "Uygulama yüklü kalacak.")
        }
        return userDataSelected ? String(localized: "Seçili kullanıcı verileri de kaldırılacak.") : String(localized: "Kullanıcı verisi seçilmedi.")
    }
    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
    private var removalTitle: String {
        if !preparation.processes.isEmpty { return String(localized: "Kapat ve Kaldır…") }
        return removesHomebrewApplication ? String(localized: "Homebrew ile Kaldır…") : String(localized: "Seçilenleri Çöp’e Taşı")
    }
    private var confirmationAction: String {
        if forceConfirmation { return String(localized: "Zorla Kapat ve Kaldır") }
        if !preparation.processes.isEmpty { return String(localized: "Kapat ve Devam Et") }
        return removesHomebrewApplication ? String(localized: "Homebrew ile Kaldır") : String(localized: "Çöp’e Taşı")
    }
    private var confirmationMessage: String {
        let files = removesHomebrewApplication ? String(localized: "\(plan.application.name) ve paket kaydı Homebrew tarafından kaldırılır. Uygulamanın kendisi Çöp’e gitmeyebilir; geri almak için yeniden kurman gerekir. Seçili ilişkili dosyalar Çöp’e taşınır.") :
            String(localized: "\(plan.application.name) için \(confirmedSelection.count) öğe seçildi. Seçili kullanıcı verileri de taşınır. Gerekirse Finder’daki Çöp’ten geri alabilirsin.")
        let closing = forceConfirmation ? String(localized: "Listelenen süreçler zorla kapatılacak. Kaydedilmemiş çalışmalar kaybolabilir. Süreç listesi değişirse yeniden onay gerekir.") :
            String(localized: "Çalışan uygulamaya önce normal çıkış isteği gönderilir. Kaydetme penceresi açılırsa yanıtla; uygulama ve yardımcıları kapanmadan dosyalar kaldırılmaz.")
        return closing + "\n\n" + files
    }
    private func askConfirmation(force: Bool) {
        forceConfirmation = force; confirmedSelection = selected; forceConsent = force ? preparation.forceIdentities : []; confirm = true
    }
    private func execute() {
        let selection = confirmedSelection, consent = forceConfirmation ? forceConsent : nil
        pending = true; operationError = nil
        work = Task { @MainActor in
            defer { pending = false; work = nil }
            guard await preparation.prepare(forceConsent: consent), !Task.isCancelled else { return }
            if await model.uninstall(plan, selected: selection) { dismiss() }
            else {
                operationError = [model.resultMessage, model.failure ?? String(localized: "Kaldırma tamamlanamadı.")]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
    }
}
