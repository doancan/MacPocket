import Combine
import Foundation
import MacPocketCore

@MainActor final class CableImpactModel: ObservableObject {
    typealias Read = @Sendable () async throws -> CableInventory
    typealias Scan = @Sendable (CableConnection, CableInventory, Set<String>, Set<String>) async throws -> CableImpactReport
    @Published private(set) var inventory: CableInventory?
    @Published private(set) var selectedID: String?
    @Published private(set) var report: CableImpactReport?
    @Published private(set) var loading = false
    @Published private(set) var scanning = false
    @Published private(set) var failure: String?
    @Published private(set) var loaded = false
    @Published private(set) var mappingNotice: String?
    @Published private(set) var additionalConnections: [String: Set<String>] = [:]
    @Published private(set) var manualEndpoints: [String: Set<String>] = [:]
    private let read: Read
    private let scan: Scan
    private let stillPresent: @Sendable (Set<UInt64>) -> Bool
    private var generation = UUID()
    private var scanTask: Task<Void, Never>?

    init(read: @escaping Read = { try await CableResourceReader.read() },
         scan: @escaping Scan = { try await CableImpactScanner.scan(connection: $0, inventory: $1, additionalConnections: $2, manualEndpoints: $3) },
         stillPresent: @escaping @Sendable (Set<UInt64>) -> Bool = { CableRegistryReader.entriesStillPresent($0) }) {
        self.read = read
        self.scan = scan
        self.stillPresent = stillPresent
    }
    var selection: CableConnection? { inventory?.connections.first { $0.id == selectedID } }
    var affected: [CableAffectedEndpoint] {
        if let report, report.connectionID == selectedID { return report.affected }
        guard let inventory, let selection else { return [] }
        return CableTopology.affected(connection: selection, inventory: inventory,
                                       additionalConnections: additionalConnections[selection.id] ?? [], manualEndpoints: manualEndpoints[selection.id] ?? [])
    }
    var unassigned: [CableEndpoint] {
        let known = Set(affected.filter { $0.evidence == .registry }.map(\.id))
        return (inventory?.endpoints ?? []).filter { $0.kind != .usb && !known.contains($0.id) }
    }
    func run() async {
        await refresh()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let inventory else { continue }
            let fresh = await Task.detached(priority: .utility) { CableRegistryReader.read() }.value
            guard !Task.isCancelled else { return }
            let oldIDs = Set(inventory.nodes.filter { $0.kind != .service })
            let newIDs = Set(fresh.nodes.filter { $0.kind != .service })
            if fresh.complete && oldIDs != newIDs { await refresh() }
        }
    }
    func refresh() async {
        guard !loading else { return }
        generation = UUID()
        scanTask?.cancel()
        scanTask = nil
        let token = generation
        loading = true
        scanning = false
        report = nil
        failure = nil
        defer { if token == generation { loading = false } }
        do {
            let fresh = try await read()
            try Task.checkCancellation()
            guard token == generation else { return }
            if let previous = inventory {
                let oldNodes = Set(previous.nodes.filter { $0.kind != .service })
                let newNodes = Set(fresh.nodes.filter { $0.kind != .service })
                if oldNodes != newNodes, additionalConnections.values.contains(where: { !$0.isEmpty }) || manualEndpoints.values.contains(where: { !$0.isEmpty }) {
                    additionalConnections = [:]
                    manualEndpoints = [:]
                    mappingNotice = String(localized: "Donanım bağlantısı değişti; elle eşleştirmeler sıfırlandı.")
                }
            }
            inventory = fresh
            loaded = true
            let ids = Set(fresh.connections.map(\.id)), endpointIDs = Set(fresh.endpoints.map(\.id))
            additionalConnections = additionalConnections.filter { ids.contains($0.key) }.mapValues { $0.intersection(ids) }
            manualEndpoints = manualEndpoints.filter { ids.contains($0.key) }.mapValues { $0.intersection(endpointIDs) }
            if selectedID.map(ids.contains) != true { selectedID = fresh.connections.first?.id }
            loading = false
            startScan()
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            inventory = nil
            report = nil
            selectedID = nil
            loaded = true
            failure = error.localizedDescription
        }
    }
    func select(_ id: String?) {
        guard !loading, selectedID != id else { return }
        selectedID = id
        startScan()
    }
    func pairConnection(_ id: String, enabled: Bool) {
        guard !loading, let selectedID, id != selectedID, inventory?.connections.contains(where: { $0.id == id }) == true else { return }
        if enabled { additionalConnections[selectedID, default: []].insert(id) }
        else { additionalConnections[selectedID]?.remove(id) }
        startScan()
    }
    func pairEndpoint(_ id: String, enabled: Bool) {
        guard !loading, let selectedID, inventory?.endpoints.contains(where: { $0.id == id }) == true else { return }
        if enabled { manualEndpoints[selectedID, default: []].insert(id) }
        else { manualEndpoints[selectedID]?.remove(id) }
        startScan()
    }
    private func startScan() {
        generation = UUID()
        let token = generation
        scanTask?.cancel()
        report = nil
        failure = nil
        scanning = false
        guard let inventory, let selection else { return }
        scanning = true
        let extra = additionalConnections[selection.id] ?? [], manual = manualEndpoints[selection.id] ?? []
        scanTask = Task { [weak self, scan, stillPresent] in
            do {
                let result = try await scan(selection, inventory, extra, manual)
                try Task.checkCancellation()
                guard let self, generation == token else { return }
                var roots = inventory.connections.filter { $0.id == selection.id || extra.contains($0.id) }.reduce(into: Set<UInt64>()) { $0.formUnion($1.roots) }
                roots.formUnion(result.affected.flatMap { $0.endpoint.registryIDs })
                let present = await Task.detached(priority: .utility) { stillPresent(roots) }.value
                guard generation == token, !Task.isCancelled else { return }
                guard present else {
                    scanning = false
                    report = nil
                    self.inventory = nil
                    selectedID = nil
                    failure = String(localized: "Seçilen bağlantı değişti veya çıkarıldı. Etki haritasını yenile.")
                    return
                }
                report = result
                scanning = false
            } catch {
                guard let self, generation == token, !Task.isCancelled else { return }
                failure = error.localizedDescription
                scanning = false
            }
        }
    }
    func stop() {
        generation = UUID()
        scanTask?.cancel()
        scanTask = nil
        loading = false
        scanning = false
    }
    func cancel() {
        stop()
        report = nil
        failure = String(localized: "Denetim iptal edildi. Yenile ile yeniden dene.")
    }
}
