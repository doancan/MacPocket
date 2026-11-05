import CoreLocation
import Foundation
import MacPocketCore

/// Fetches an approximate location once (at most daily) for the night schedule's sunrise/sunset times.
@MainActor
final class NightLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let fetchedAtKey = "MacPocket.night.locationFetchedAt"
    /// Farther than this from every catalog city, the location is shown as coordinates instead of a misleading name.
    static let cityNameRadiusKilometers = 150.0

    @Published private(set) var authorization: CLAuthorizationStatus
    var onLocation: (Coordinate, String?) -> Void = { _, _ in }

    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private var isRequesting = false
    private var isRequestPending = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Asks for authorization if needed, then requests a single location. Refreshes at most once per day unless
    /// `force` (the user asked for it explicitly).
    func request(force: Bool = false) {
        if force { defaults.removeObject(forKey: Self.fetchedAtKey) }
        guard LocationRefreshPolicy.shouldFetch(lastFetch: defaults.object(forKey: Self.fetchedAtKey) as? Date, now: Date()) else {
            return
        }
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined:
            isRequestPending = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            requestLocation()
        default:
            break
        }
    }

    func cancel() {
        isRequesting = false
        isRequestPending = false
        manager.stopUpdatingLocation()
    }

    private func requestLocation() {
        guard !isRequesting,
              LocationRefreshPolicy.shouldFetch(lastFetch: defaults.object(forKey: Self.fetchedAtKey) as? Date, now: Date())
        else { return }
        isRequesting = true
        manager.requestLocation()
    }

    private func handle(location: CLLocation) {
        guard isRequesting else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        // Named offline after the nearest catalog city: the location never leaves the Mac (no reverse geocoding).
        let name = CityCatalog.nearest(to: coordinate, within: Self.cityNameRadiusKilometers)?.name
        defaults.set(Date(), forKey: Self.fetchedAtKey)
        isRequesting = false
        onLocation(coordinate, name)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            // Fires once on delegate assignment and on every change; only fetch for a pending request().
            if self.isRequestPending, status == .authorizedAlways {
                self.isRequestPending = false
                self.requestLocation()
            } else if status != .notDetermined {
                self.isRequestPending = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handle(location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.isRequesting = false }
    }
}
