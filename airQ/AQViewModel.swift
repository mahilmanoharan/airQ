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
        
        do {
            let airQuality = try await airQualityTask
            let pollen = try? await pollenTask

            state = .loaded(airQuality, pollen)
            updateWidgetSnapshot(with: airQuality)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func updateWidgetSnapshot(with airQuality: AirQuality) {
        let locationName = airQuality.data.city.name.isEmpty ? "Current Location" : airQuality.data.city.name
        let snapshot = AQSnapshot(
            aqi: airQuality.data.aqi,
            locationName: locationName,
            lastUpdated: Date()
        )
        WidgetDataStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "airQWidget")
    }
}

