import Foundation
import MacPocketCore
import MapKit

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    private static let locationKey = "MacPocket.weather.location"
    @Published private(set) var location: WeatherLocation?
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var enabled = false
    private var refreshTimer: Task<Void, Never>?
    private var fetch: Task<Void, Never>?
    private var generation = UUID()
    private var lastAttempt = Date.distantPast

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.locationKey),
           let stored = try? JSONDecoder().decode(WeatherLocation.self, from: data), stored.isValid { location = stored }
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        refreshTimer?.cancel(); refreshTimer = nil
        if !enabled { generation = UUID(); fetch?.cancel(); loading = false; return }
        refresh()
    }

    /// No polling while idle: one cancellable wakeup at the next actual refresh deadline.
    private func scheduleRefresh() {
        refreshTimer?.cancel()
        refreshTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func select(_ location: WeatherLocation) {
        guard location.isValid else { return }
        generation = UUID(); fetch?.cancel(); refreshTimer?.cancel(); loading = false
        self.location = location; snapshot = nil; error = nil
        if let data = try? JSONEncoder().encode(location) { UserDefaults.standard.set(data, forKey: Self.locationKey) }
        lastAttempt = .distantPast
        refresh()
    }

    func refresh(manual: Bool = false) {
        guard enabled, !loading, let location else { return }
        guard !manual || Date().timeIntervalSince(lastAttempt) >= 60 else { return }
        let token = generation
        loading = true; error = nil
        lastAttempt = Date()
        scheduleRefresh()
        fetch = Task { [weak self] in
            do {
                let language = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "tr"
                let result = try await WeatherClient.fetch(location: location, language: language)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.snapshot = result
                self.loading = false
            } catch {
                guard let self, self.generation == token else { return }
                self.loading = false
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    var canRefresh: Bool { !loading && Date().timeIntervalSince(lastAttempt) >= 60 }
}

/// Place lookup needs a search phrase, not permission to read the user's current location.
@MainActor
enum WeatherLocationSearch {
    static func find(_ query: String) async throws -> [WeatherLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        try Task.checkCancellation()
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            let coordinate = item.location.coordinate
            let location = WeatherLocation(name: item.address?.fullAddress ?? item.name ?? query,
                                           latitude: coordinate.latitude, longitude: coordinate.longitude,
                                           timeZone: item.timeZone?.identifier ?? TimeZone.current.identifier)
            return location.isValid && seen.insert(location.id).inserted ? location : nil
        }.prefix(6).map { $0 }
    }
}
