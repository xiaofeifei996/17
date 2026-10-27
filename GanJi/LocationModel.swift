import SwiftUI
import CoreLocation

final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var heading: CLLocationDirection = 0
    @Published var horizontalAccuracy: CLLocationAccuracy = -1
    @Published var denied = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 2
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startSensors()
        default:
            denied = true
        }
    }

    private func startSensors() {
        denied = false
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startSensors()
        case .denied, .restricted:
            denied = true
            manager.stopUpdatingHeading()
            manager.stopUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            self.latitude = loc.coordinate.latitude
            self.longitude = loc.coordinate.longitude
            self.horizontalAccuracy = loc.horizontalAccuracy
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        DispatchQueue.main.async { self.heading = value }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
