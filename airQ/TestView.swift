import SwiftUI
import CoreLocation

/// Simple test view that bypasses location and directly fetches AQI
struct TestView: View {
    @State private var aqiData: AirQuality?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("AQI Test View")
                .font(.title)
                .fontWeight(.bold)
            
            if isLoading {
                ProgressView()
                Text("Loading...")
            } else if let data = aqiData {
                VStack(spacing: 12) {
                    Text(data.data.city.name)
                        .font(.title2)
                    
                    Text("\(data.data.aqi)")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(aqiColor(for: data.data.aqi))
                    
                    Text("AQI")
                        .font(.headline)
                }
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
            
            Button("Test San Francisco") {
                testLocation(lat: 37.7749, lon: -122.4194, name: "San Francisco")
            }
            .buttonStyle(.borderedProminent)
            
            Button("Test New York") {
                testLocation(lat: 40.7128, lon: -74.0060, name: "New York")
            }
            .buttonStyle(.borderedProminent)
            
            Button("Test London") {
                testLocation(lat: 51.5074, lon: -0.1278, name: "London")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func testLocation(lat: Double, lon: Double, name: String) {
        isLoading = true
        errorMessage = nil
        aqiData = nil
        
        Task {
            do {
                print("🧪 Testing \(name): \(lat), \(lon)")
                let data = try await fetchAQ(latitude: lat, longitude: lon)
                await MainActor.run {
                    aqiData = data
                    isLoading = false
                    print("✅ Success! AQI: \(data.data.aqi)")
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                    print("❌ Error: \(error)")
                }
            }
        }
    }
    
    private func aqiColor(for aqi: Int) -> Color {
        switch aqi {
        case 0...50: return .green
        case 51...100: return .yellow
        case 101...150: return .orange
        case 151...200: return .red
        case 201...300: return .purple
        default: return .brown
        }
    }
}

#Preview {
    TestView()
}
