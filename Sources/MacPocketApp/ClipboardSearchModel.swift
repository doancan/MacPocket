import Combine
import Foundation
import MacPocketCore

/// Shared asynchronous search and selection for the browser and the floating panel.
@MainActor final class ClipboardSearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { restart(debounce: true) } } }
    @Published var kind: ClipboardContent.Kind? { didSet { if kind != oldValue { restart(debounce: false) } } }
    @Published var selectedIndex = 0
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isSearching = false
    let service: ClipboardService
    private let delay: Duration
    private let search: @MainActor (String, ClipboardContent.Kind?) async throws -> [ClipboardItem]
    private var subscription: AnyCancellable?
    private var active = false
    private var task: Task<Void, Never>?
    private var request: UInt64 = 0
    private var snapshot: ClipboardHistory

    init(service: ClipboardService, delay: Duration = .milliseconds(120),
         search: (@MainActor (String, ClipboardContent.Kind?) async throws -> [ClipboardItem])? = nil) {
        self.service = service; self.delay = delay; self.snapshot = service.history
        self.search = search ?? { query, kind in try await service.search(query, kind: kind) }
        start()
    }

    func start() {
        guard !active else { return }
        active = true
        subscription = service.$history.sink { [weak self] history in
            guard let self else { return }
            self.snapshot = history
            self.restart(debounce: false)
        }
    }

    func stop() {
        active = false
        request &+= 1
        task?.cancel(); task = nil
        subscription?.cancel(); subscription = nil
        items = []; selectedIndex = 0; isSearching = false
    }

    private func restart(debounce: Bool) {
        guard active else { return }
        request &+= 1
        let current = request, query = query, kind = kind
        task?.cancel(); task = nil
        selectedIndex = 0
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            items = snapshot.search("", kind: kind)
            isSearching = false
            return
        }
        // Never let Enter, digit shortcuts or a stale row paste a result from the previous request.
        items = []; isSearching = true
        task = Task { [weak self, search, delay] in
            do {
                if debounce { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                let result = try await search(query, kind)
                try Task.checkCancellation()
                guard let self, self.request == current else { return }
                self.items = result; self.isSearching = false; self.task = nil
            } catch {
                guard let self, self.request == current else { return }
                self.isSearching = false; self.task = nil
            }
        }
    }

    var selectedItem: ClipboardItem? {
        guard !isSearching else { return nil }
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : items.first
    }

    func move(by offset: Int) {
        guard !items.isEmpty, !isSearching else { return }
        selectedIndex = min(max(0, selectedIndex + offset), items.count - 1)
    }

    isolated deinit { stop() }
}
