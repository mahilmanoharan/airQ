import Foundation
import Observation
import CoreLocation
import WidgetKit
import AirQualityKit

// MARK: - View State

enum ViewState {
    case loading
    case loaded(AirQuality, Pollen?)
    case error(String)
}

// MARK: - ViewModel

@Observable
class DashboardViewModel {
    
    // MARK: - Properties
    
    var state: ViewState = .loading
    var cityName: String?
    let locationManager = LocationManager()

    // MARK: - Methods
    
    func loadAirQuality() {
        state = .loading
        
        locationManager.requestLocation()
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard locationManager.location == nil else { return }
            state = .error("Location not found")
        }
    }
    
    func fetchAirQualityData(latitude: Double, longitude: Double) async {
        state = .loading

        async let airQualityTask = fetchAQ(latitude: latitude, longitude: longitude)
        async let pollenTask = fetchPollen(latitude: latitude, longitude: longitude)
        async let cityNameTask = locationManager.reverseGeocodedCityName(
            for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )

        do {
            let airQuality = try await airQualityTask
            let pollen = try? await pollenTask
            let cityName = await cityNameTask

            self.cityName = cityName
            state = .loaded(airQuality, pollen)
            updateWidgetSnapshot(with: airQuality, cityName: cityName)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func updateWidgetSnapshot(with airQuality: AirQuality, cityName: String?) {
        let snapshot = AQSnapshot(
            aqi: airQuality.data.aqi,
            locationName: cityName ?? Self.fallbackLocationName(from: airQuality.data.city.name),
            lastUpdated: Date()
        )
        WidgetDataStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "airQWidget")
    }

    /// Used only when reverse geocoding fails (offline, denied, no placemark) — takes the
    /// first comma-separated segment of the data provider's raw station name as a rough stand-in.
    private static func fallbackLocationName(from fullName: String) -> String {
        guard !fullName.isEmpty else { return "Current Location" }
        let firstComponent = fullName.split(separator: ",", maxSplits: 1).first ?? Substring(fullName)
        return firstComponent.trimmingCharacters(in: .whitespaces)
    }
}

