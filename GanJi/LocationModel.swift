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
        // Ignore invalid compass readings; poor accuracy can otherwise make the map jump.
        guard newHeading.headingAccuracy >= 0 else { return }
        let raw = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let normalized = (raw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        DispatchQueue.main.async {
            // Circular interpolation handles the 359° -> 0° boundary without spinning backwards.
            let current = self.heading
            var delta = normalized - current
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            let smoothed = (current + delta * 0.28).truncatingRemainder(dividingBy: 360)
            self.heading = smoothed < 0 ? smoothed + 360 : smoothed
        }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
