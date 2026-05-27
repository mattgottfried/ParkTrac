import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var userCoordinate: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100   // update only when user moves 100m+
    }

    func requestAndStart() {
        manager.requestWhenInUseAuthorization()
        // startUpdatingLocation is also called in locationManagerDidChangeAuthorization
        // when status changes to authorizedWhenInUse — calling it here handles the case
        // where permission was already granted on a previous launch
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Returns the park the user is physically inside (within 2 km of its center), or nil if not near any park.
    func nearestPark(from parks: [ParkEntity]) -> ParkEntity? {
        guard let userCoord = userCoordinate,
              CLLocationCoordinate2DIsValid(userCoord) else { return nil }
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        return parks
            .compactMap { park -> (ParkEntity, CLLocationDistance)? in
                guard let c = park.coordinate, CLLocationCoordinate2DIsValid(c) else { return nil }
                let dist = userLoc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                return dist < 2_000 ? (park, dist) : nil
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userCoordinate = locations.last?.coordinate
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently ignore — the map works fine without location
    }
}
