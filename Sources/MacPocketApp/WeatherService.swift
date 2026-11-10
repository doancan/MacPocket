import Foundation
import MacPocketCore
import MapKit

@MainActor
@Observable

final class WeatherService {
    static let shared = WeatherService()
    private static let locationKey = "MacPocket.weather.location"
    private static let basketKey = "MacPocket.weather.sources"
    private(set) var location: WeatherLocation?
    private(set) var snapshot: WeatherSnapshot?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var basket: WeatherBasket
    private(set) var configuredKeys: Set<WeatherSource>
    private(set) var credentialError: String?
    private(set) var nextRefreshAt: Date?
    private let defaults: UserDefaults
    private let credentials: any WeatherCredentialStoring
    private let client: @Sendable (WeatherSource, WeatherLocation, String, String?) async throws -> WeatherSnapshot
    private let now: () -> Date
    private struct CacheKey: Hashable {
        let source: WeatherSource, locationID: String, zone: String, name: String
    }
    @ObservationIgnored private var cache: [CacheKey: WeatherSnapshot] = [:]
    @ObservationIgnored private var attempts: [CacheKey: Date] = [:]
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var refreshTimer: Task<Void, Never>?
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    init(defaults: UserDefaults = .standard, credentials: any WeatherCredentialStoring = WeatherKeychainStore(),
         now: @escaping () -> Date = Date.init,
         client: @escaping @Sendable (WeatherSource, WeatherLocation, String, String?) async throws -> WeatherSnapshot = {
            try await WeatherProviderClient.fetch(source: $0, location: $1, language: $2, apiKey: $3)
         }) {
        self.defaults = defaults; self.credentials = credentials; self.client = client; self.now = now
        let stored = defaults.data(forKey: Self.locationKey).flatMap { try? JSONDecoder().decode(WeatherLocation.self, from: $0) }
        let restoredLocation = stored.flatMap { $0.isValid ? $0 : nil }
        basket = .restored(defaults.data(forKey: Self.basketKey), hasExistingLocation: restoredLocation != nil)
        configuredKeys = Set(WeatherSource.catalog.filter { $0.requiresAPIKey && credentials.contains($0) })
        location = restoredLocation
    }

    var activeSource: WeatherSource { basket.active }
    func include(_ source: WeatherSource, included: Bool) {
        let previous = activeSource
        basket.include(source, included: included); persistBasket()
        if previous != activeSource { invalidate(); refresh() }
    }
    func selectSource(_ source: WeatherSource) {
        guard activeSource != source else { return }
        basket.select(source); persistBasket(); invalidate(); refresh()
    }
    private func persistBasket() {
        if let data = try? JSONEncoder().encode(basket) { defaults.set(data, forKey: Self.basketKey) }
    }
    @discardableResult func saveKey(_ value: String?, for source: WeatherSource) -> Bool {
        guard source.requiresAPIKey else { return false }
        do {
            let validated = try value.map { try WeatherSourceError.validatedKey($0) }
            try credentials.save(validated, for: source)
            if validated == nil { configuredKeys.remove(source) } else { configuredKeys.insert(source) }
            cache = cache.filter { $0.key.source != source }; attempts = attempts.filter { $0.key.source != source }
            credentialError = nil
            if activeSource == source { invalidate(); refresh() }
            return true
        } catch { credentialError = error.localizedDescription; return false }
    }
    private func invalidate() {
        generation = UUID(); fetch?.cancel(); refreshTimer?.cancel(); loading = false
        snapshot = nil; error = nil; nextRefreshAt = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        refreshTimer?.cancel(); refreshTimer = nil
        if !enabled { generation = UUID(); fetch?.cancel(); loading = false; return }
        refresh()
    }

    /// No polling while idle: one cancellable wakeup at the next actual refresh deadline.
    private func scheduleRefresh(at date: Date) {
        refreshTimer?.cancel()
        refreshTimer = Task { [weak self] in
            let delay = max(1, date.timeIntervalSince(self?.now() ?? Date()))
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func select(_ location: WeatherLocation) {
        guard location.isValid else { return }
        invalidate(); self.location = location
        if let data = try? JSONEncoder().encode(location) { defaults.set(data, forKey: Self.locationKey) }
        refresh()
    }

    func refresh(manual: Bool = false) {
        guard enabled, !loading, let location else { return }
        let source = activeSource, date = now()
        let key = CacheKey(source: source, locationID: location.id, zone: location.timeZone, name: location.name)
        if let cached = cache[key], let deadline = cached.nextRefreshAt, deadline > date {
            snapshot = cached; error = nil; nextRefreshAt = deadline; scheduleRefresh(at: deadline); return
        }
        if let attempt = attempts[key], date.timeIntervalSince(attempt) < 60 {
            nextRefreshAt = attempt.addingTimeInterval(60); scheduleRefresh(at: nextRefreshAt!); return
        }
        let apiKey: String?
        do { apiKey = source.requiresAPIKey ? try credentials.read(source) : nil
            if source.requiresAPIKey { _ = try WeatherSourceError.validatedKey(apiKey) }
        } catch { self.error = error.localizedDescription; return }
        let token = generation
        loading = true; error = nil
        attempts[key] = date; nextRefreshAt = date.addingTimeInterval(60)
        let client = client
        fetch = Task { [weak self] in
            do {
                let language = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "tr"
                var result = try await client(source, location, language, apiKey)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                result.source = source
                result.nextRefreshAt = max(result.nextRefreshAt ?? .distantPast, date.addingTimeInterval(source.refreshInterval))
                self.cache[key] = result
                self.snapshot = result
                self.loading = false
                self.nextRefreshAt = result.nextRefreshAt
                self.scheduleRefresh(at: result.nextRefreshAt!)
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.loading = false
                self.error = error.localizedDescription
                let delay: TimeInterval = error as? WeatherSourceError == .rateLimited ? source.refreshInterval : 60
                self.nextRefreshAt = self.now().addingTimeInterval(delay)
                self.attempts[key] = self.now().addingTimeInterval(delay - 60)
                self.scheduleRefresh(at: self.now().addingTimeInterval(max(delay, source.refreshInterval)))
            }
        }
    }

    var canRefresh: Bool {
        canRefresh(at: now())
    }
    func canRefresh(at date: Date) -> Bool {
        enabled && location != nil && !loading && date >= (nextRefreshAt ?? .distantPast)
            && (!activeSource.requiresAPIKey || configuredKeys.contains(activeSource))
    }
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
