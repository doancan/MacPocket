import CoreLocation
import Foundation
import MacPocketCore

/// Fetches an approximate location once (at most daily) for the night schedule's sunrise/sunset times.
@MainActor
final class NightLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let fetchedAtKey = "MacPocket.night.locationFetchedAt"

    @Published private(set) var authorization: CLAuthorizationStatus
    var onLocation: (Coordinate, String?) -> Void = { _, _ in }

    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private var isRequesting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Asks for authorization if needed, then requests a single location. Refreshes at most once per day.
    func request() {
        if let last = defaults.object(forKey: Self.fetchedAtKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            requestLocation()
        default:
            break
        }
    }

    private func requestLocation() {
        guard !isRequesting else { return }
        isRequesting = true
        manager.requestLocation()
    }

    private func handle(location: CLLocation) async {
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let name = placemarks?.first?.locality
        defaults.set(Date(), forKey: Self.fetchedAtKey)
        isRequesting = false
        onLocation(coordinate, name)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways || status == .authorized {
                self.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.handle(location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.isRequesting = false }
    }
}
