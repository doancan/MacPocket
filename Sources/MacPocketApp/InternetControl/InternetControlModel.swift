import AppKit
import Combine
import MacPocketCore
import MacPocketNetworkPolicy
import NetworkExtension
import Security
import SystemExtensions

@MainActor final class InternetControlModel: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let extensionID = "com.doancan.MacPocket.NetworkFilter"
    @Published private(set) var policy: AppNetworkPolicy
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var extensionReady = false
    @Published private(set) var policyApplied = false
    @Published private(set) var configurationKnown = false
    @Published private(set) var policyReadable = true
    @Published private(set) var message: String?
    @Published private(set) var connections: [OpenConnection.Group] = []
    @Published private(set) var readingConnections = false
    @Published private(set) var connectionsLoaded = false
    private var pendingRequest: OSSystemExtensionRequest?
    private let manager = NEFilterManager.shared()
    private let defaults: UserDefaults
    var packaged: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(Self.extensionID).systemextension").path)
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: "MacPocket.internetControl.policy")
        let data = stored as? Data
        let decoded = data.flatMap { try? AppNetworkPolicy.decode($0) }
        policy = decoded ?? .init()
        super.init()
        if stored != nil && decoded == nil {
            policyReadable = false
            message = String(localized: "Kayıtlı ağ kuralları okunamadı. Mevcut veri korunuyor; uygulamadan önce kuralları sıfırla.")
        }
    }
    func reload() async {
        guard packaged else { message = String(localized: "Filtre uzantısı bu pakette yok. Network Extension imzalama profiliyle filtreli paket hazırlanmalı."); return }
        do {
            try await manager.loadFromPreferences()
            enabled = manager.isEnabled
            configurationKnown = true
            if let data = manager.providerConfiguration?.vendorConfiguration?["policy"] as? Data {
                policyApplied = (try? AppNetworkPolicy.decode(data)) == policy
            }
            let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main)
            request.delegate = self
            pendingRequest = request
            OSSystemExtensionManager.shared.submitRequest(request)
        }
        catch { message = error.localizedDescription }
    }
    func addApplication() {
        guard policyReadable, !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let identity = ApplicationSigningIdentity.read(at: url) else {
            message = String(localized: "Uygulamanın kod imzası doğrulanamadı.")
            return
        }
        let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        var rules = policy.rules.filter { $0.identity != identity }
        guard rules.count < 512 else { return }
        rules.append(.init(identity: identity, name: name))
        policy.rules = rules
        persist()
    }

    func setAction(_ action: AppNetworkAction, for id: AppNetworkIdentity) {
        guard !busy, let index = policy.rules.firstIndex(where: { $0.id == id }) else { return }
        policy.rules[index].action = action
        persist()
    }
    func remove(_ id: AppNetworkIdentity) { guard !busy else { return }; policy.rules.removeAll { $0.id == id }; persist() }
    private func persist() {
        guard policyReadable else { return }
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: "MacPocket.internetControl.policy")
        policyApplied = false
        message = String(localized: "Kurallar kaydedildi. Filtreye göndermek için Kuralları Uygula’yı kullan.")
    }
    func activate() {
        guard packaged, !busy else { return }
        busy = true
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main)
        request.delegate = self
        pendingRequest = request
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    func apply(enabled: Bool) async {
        guard packaged, !busy, !enabled || (extensionReady && policyReadable) else { return }
        busy = true
        defer { busy = false }
        do {
            try await manager.loadFromPreferences()
            if enabled {
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterDataProviderBundleIdentifier = Self.extensionID
                configuration.vendorConfiguration = ["policy":try JSONEncoder().encode(policy)]
                manager.providerConfiguration = configuration
            }
            manager.localizedDescription = String(localized: "MacPocket İnternet Kontrolü")
            manager.isEnabled = enabled
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            self.enabled = manager.isEnabled
            configurationKnown = true
            policyApplied = enabled
            message = enabled ? String(localized: "Filtre yapılandırması kaydedildi. Kurallar yeni bağlantılara uygulanır.") : String(localized: "İnternet filtresi kapatıldı.")
        } catch { message = error.localizedDescription }
    }
    func resetUnreadablePolicy() {
        guard !busy else { return }
        policy = .init()
        policyReadable = true
        persist()
    }
    func refreshConnections() async {
        guard !readingConnections else { return }
        readingConnections = true
        defer { readingConnections = false; connectionsLoaded = true }
        do {
            let result = try await BoundedProcess.run("/usr/sbin/lsof", ["-n", "-P", "-iTCP", "-iUDP", "-Fpcn"], timeout: 8)
            guard !Task.isCancelled else { return }
            connections = OpenConnection.grouped(OpenConnection.parseLsof(result.output))
            if result.status != 0 && result.status != 1 { message = String(localized: "Bağlantı listesi okunamadı.") }
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        let token = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == token else { return }
            self.message = String(localized: "Sistem Ayarları’nda MacPocket ağ uzantısına izin ver.") }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let completed = result == .completed, token = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == token else { return }
            self.busy = false
            self.pendingRequest = nil
            self.extensionReady = completed
            self.message = completed ? String(localized: "Uzantı isteği tamamlandı. Kuralları uygulayabilirsin.") : String(localized: "Uzantı kurulumu yeniden başlatma bekliyor.")
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let ready = properties.contains { $0.isEnabled && !$0.isUninstalling && !$0.isAwaitingUserApproval }
        let token = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == token else { return }
            self.extensionReady = ready
            self.pendingRequest = nil
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message = error.localizedDescription, token = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == token else { return }
            self.busy = false
            self.pendingRequest = nil
            self.message = message
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
