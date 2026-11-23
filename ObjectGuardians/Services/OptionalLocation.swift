import Foundation
import CoreLocation

final class OptionalLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var value: String?
    @Published var status: String = "Attach location (optional)"
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func ask() {
        let authorization = manager.authorizationStatus
        if authorization == .notDetermined {
            status = "Waiting for permission..."
            manager.requestWhenInUseAuthorization()
        } else if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            status = "Locating..."
            manager.requestLocation()
        } else { status = "Location not shared" }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            status = "Locating..."
            manager.requestLocation()
        case .denied, .restricted: status = "Location not shared"
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        value = String(format:"%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        status = "Location attached ✓"
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let place = placemarks?.first,
                  let street = place.thoroughfare ?? place.locality, !street.isEmpty else { return }
            DispatchQueue.main.async { self?.value = street }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Couldn't get location (optional)"
    }
}
