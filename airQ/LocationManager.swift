import Foundation
import CoreLocation
import MapKit
import Observation

// MARK: - Location Manager

@Observable
class LocationManager: NSObject {
    
    // MARK: - Properties
    
    var location: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    // MARK: - Initialization

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Methods

    func requestLocation() {

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            print("Authorization denied or restricted")
        @unknown default:
            print("Unknown authorization status")
        }
    }

    /// Resolves a coordinate to a real place name (e.g. "San Francisco"), the same way
    /// Apple Weather does, rather than relying on a data provider's station-name string.
    /// Returns nil on failure so callers can fall back to another source.
    func reverseGeocodedCityName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            guard let placemark = mapItems.first?.placemark else { return nil }
            return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        } catch {
            print("Reverse geocoding failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }
        
        location = newLocation.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}

// MARK: - CLAuthorizationStatus Extension

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Authorized Always"
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        @unknown default:
            return "Unknown"
        }
    }
}
