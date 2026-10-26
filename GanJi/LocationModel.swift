import SwiftUI
import CoreLocation

final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var denied = false
    @Published var heading: Double = 0
    @Published var headingAvailable = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.headingFilter = 2
    }

    func start() {
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            denied = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            denied = false
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            denied = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard value >= 0 else { return }
        heading = value
        headingAvailable = true
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
