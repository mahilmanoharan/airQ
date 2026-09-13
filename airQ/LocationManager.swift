import AirQualityKit
import CoreLocation
import MapKit

enum LocationError: LocalizedError {
    case denied, restricted, unavailable, requestInProgress

    var errorDescription: String? {
        switch self {
        case .denied: "Enable location access in Settings to see local air quality."
        case .restricted: "Location services are restricted on this device."
        case .unavailable: "Your location is unavailable. Please try again."
        case .requestInProgress: "A location request is already in progress."
        }
    }
}

/// One cancellable request, with city-level accuracy appropriate for regional readings.
@MainActor
final class LocationManager: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<GeoCoordinate, any Error>?
    private var requestID: UUID?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate() async throws -> GeoCoordinate {
        try Task.checkCancellation()
        guard pending == nil else { throw LocationError.requestInProgress }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                pending = $0
                requestID = id
                requestIfAuthorized()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestID == id else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func cityName(for coordinate: GeoCoordinate) async -> String? {
        guard !Task.isCancelled,
              let request = MKReverseGeocodingRequest(location: CLLocation(
                latitude: coordinate.latitude, longitude: coordinate.longitude
              )) else { return nil }
        do {
            let address = try await request.mapItems.first?.addressRepresentations
            return address?.cityName ?? address?.regionName
        } catch {
            return nil
        }
    }

    private func requestIfAuthorized() {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied: finish(.failure(LocationError.denied))
        case .restricted: finish(.failure(LocationError.restricted))
        @unknown default: finish(.failure(LocationError.unavailable))
        }
    }

    private func finish(_ result: Result<GeoCoordinate, any Error>) {
        let continuation = pending
        pending = nil
        requestID = nil
        manager.stopUpdatingLocation()
        continuation?.resume(with: result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else {
            finish(.failure(LocationError.unavailable))
            return
        }
        finish(.success(GeoCoordinate(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(.failure((error as? CLError)?.code == .denied ? LocationError.denied : .unavailable))
    }
}
