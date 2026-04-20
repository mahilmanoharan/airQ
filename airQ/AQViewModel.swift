import Foundation
import Observation
import CoreLocation

// MARK: - View State

enum ViewState {
    case loading
    case loaded(AirQuality)
    case error(String)
}

// MARK: - ViewModel

//@MainActor
@Observable
class DashboardViewModel {
    
    // MARK: - Properties
    
    var state: ViewState = .loading
    let locationManager = LocationManager()
    
    // Testing fallback
    private var useFallbackLocation = false
    
    // MARK: - Methods
    
    func loadAirQuality() {
        state = .loading
//        print("🚀 loadAirQuality called")
//        print("📊 Current auth status: \(locationManager.authorizationStatus.rawValue)")
//        print("📍 Current location: \(String(describing: locationManager.location))")
        
        locationManager.requestLocation()
        
        // Fallback: if location doesn't come in 3 seconds, use default
        Task {
            try? await Task.sleep(for: .seconds(3))
            if locationManager.location == nil {
//                print("⚠️ No location after 3 seconds, using fallback location (New York)")
//                print("⚠️ Final auth status: \(locationManager.authorizationStatus.rawValue)")
//                await fetchAirQualityData(latitude: 40.7128, longitude: -74.0060)
                state = .error("Location not found :(")
            } else {
//                print("✅ Location received within 3 seconds: \(locationManager.location!)")
            }
        }
    }
    
    func fetchAirQualityData(latitude: Double, longitude: Double) async {
        state = .loading
        do {
            let data = try await fetchAQ(latitude: latitude, longitude: longitude)
            state = .loaded(data)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

