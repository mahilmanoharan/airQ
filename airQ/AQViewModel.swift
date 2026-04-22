import Foundation
import Observation
import CoreLocation

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
            if locationManager.location == nil {
                state = .error("Location not found")
            } else {
            }
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
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

