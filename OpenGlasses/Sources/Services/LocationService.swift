import Foundation
import CoreLocation

/// Provides the user's current location for LLM context
@MainActor
class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var currentPlacemark: CLPlacemark?
    @Published var locationError: String?
    @Published var isAuthorized: Bool = false

    private let locationManager = CLLocationManager()
    // private let geocoder = CLGeocoder() // Deprecated in iOS 26

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100  // Update every 100m
    }

    /// Request location permissions and start updates
    func startTracking() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            isAuthorized = false
            locationError = "Location access denied"
        @unknown default:
            break
        }
    }

    /// Returns a human-readable location string for LLM context
    var locationContext: String? {
        guard let placemark = currentPlacemark else {
            guard let location = currentLocation else { return nil }
            return String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        }

        var parts: [String] = []
        if let name = placemark.name { parts.append(name) }
        if let locality = placemark.locality { parts.append(locality) }
        if let adminArea = placemark.administrativeArea { parts.append(adminArea) }
        if let country = placemark.country { parts.append(country) }

        // Deduplicate (name sometimes equals locality)
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }

        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    /// Reverse geocode the current location to get a placemark
    private func reverseGeocode(_ location: CLLocation) {
        // Disabled due to CLGeocoder deprecation warning
        /*
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                if let error = error {
                    print("📍 Geocoding failed: \(error.localizedDescription)")
                    self?.locationError = "Geocoding failed: \(error.localizedDescription)"
                    // Still have coordinates as fallback
                    return
                }

                if let placemark = placemarks?.first {
                    self?.currentPlacemark = placemark
                    print("📍 Location: \(self?.locationContext ?? "unknown")")
                } else {
                    print("📍 Geocoding returned no results")
                }
            }
        }
        */
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.reverseGeocode(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.isAuthorized = true
                manager.startUpdatingLocation()
                print("📍 Location authorized")
            case .denied, .restricted:
                self.isAuthorized = false
                self.locationError = "Location access denied"
                print("📍 Location denied")
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("📍 Location error: \(error.localizedDescription)")
            self.locationError = error.localizedDescription
        }
    }
}
