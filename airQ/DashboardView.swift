import SwiftUI
import CoreLocation

struct DashboardView: View {
    
    // MARK: - Properties
    
    @State private var vm = DashboardViewModel()

    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            
            contentView
                .padding()
        }
        .onChange(of: vm.locationManager.location?.latitude) { _, _ in
            fetchData()
        }
        .onChange(of: vm.locationManager.location?.longitude) { _, _ in
            fetchData()
        }
        .onAppear {
            vm.loadAirQuality()
        }
    }
    
    // MARK: - UI Components
    
    @ViewBuilder
    private var contentView: some View {
        switch vm.state {
        case .loading:
            loadingView
        case .loaded(let data, let pollen):
            loadedView(data: data, pollen: pollen)
        case .error(let message):
            errorView(message: message)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading air quality data...")
                .foregroundStyle(.secondary)
        }
    }
    
    private func loadedView(data: AirQuality, pollen: Pollen?) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                Text(data.data.city.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let location = data.data.city.location {
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 32) {
                // Air Quality Index Card
                VStack(spacing: 12) {
                    Text("\(data.data.aqi)")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(aqiColor(for: data.data.aqi))
                    
                    Text("AQI")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    Text(aqiCategory(for: data.data.aqi))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(aqiColor(for: data.data.aqi).opacity(0.1))
                )
                
                // Pollen Index Card
                if let pollenData = pollen, let firstDatum = pollenData.data.first {
                    let totalPollen = firstDatum.count.grassPollen + 
                                     firstDatum.count.treePollen + 
                                     firstDatum.count.weedPollen
                    
                    VStack(spacing: 12) {
                        Text("\(totalPollen)")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(pollenColor(for: totalPollen))
                        
                        Text("Pollen")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Text(pollenCategory(for: totalPollen))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(pollenColor(for: totalPollen).opacity(0.1))
                    )
                }
            }
            
            if let _ = data.data.dominentpol {
                Text("Primary Pollutant: \(data.data.dominentpol?.uppercased() ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                Text("AQI analysis")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(aqiGuidance(for: data.data.aqi))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(aqiColor(for: data.data.aqi).opacity(0.1))
            )
            
            
            if let pollenData = pollen, let firstDatum = pollenData.data.first {
                let totalPollen = firstDatum.count.grassPollen +
                firstDatum.count.treePollen +
                firstDatum.count.weedPollen
                
                VStack(spacing: 8) {
                    Text("Pollen analysis")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(pollenGuidance(for: totalPollen))
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(pollenColor(for: totalPollen).opacity(0.1))
                )
            }
            
            
            Spacer()
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text(errorMessage(message))
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Button {
                vm.loadAirQuality()
            } label: {
                Text("Retry")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue)
                    )
            }
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    
    private var backgroundColor: Color {
        switch vm.state {
        case .loaded(let data, _):
            return aqiColor(for: data.data.aqi).opacity(0.05)
        default:
            return Color(.systemBackground)
        }
    }
    
    private func aqiColor(for aqi: Int) -> Color {
        switch aqi {
        case 0...50:
            return .green
        case 51...100:
            return .yellow
        case 101...150:
            return .orange
        case 151...200:
            return .red
        case 201...300:
            return .purple
        default:
            return .brown
        }
    }
    
    private func aqiCategory(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "Good"
        case 51...100:
            return "Moderate"
        case 101...150:
            return "Unhealthy for Sensitive Groups"
        case 151...200:
            return "Unhealthy"
        case 201...300:
            return "Very Unhealthy"
        default:
            return "Hazardous"
        }
    }
    
    private func aqiGuidance(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "Air quality is satisfactory, and air pollution poses little or no risk."
        case 51...100:
            return "Air quality is acceptable. However, there may be a risk for some people who are unusually sensitive to air pollution."
        case 101...150:
            return "Members of sensitive groups may experience health effects. Use caution during outdoor activities."
        case 151...200:
            return "Some members of the general public may experience health effects. Avoid strenuous outdoor activity."
        case 201...300:
            return "Health alert: The risk of health effects is increased for everyone. Avoid outdoor activities."
        default:
            return "Health warning of emergency conditions. Everyone should avoid all outdoor physical activity."
        }
    }
    
    // MARK: - Pollen Helper Methods
    
    private func pollenGuidance(for count: Int) -> String {
        switch count {
        case 0...14:
            return "Pollen levels are low to none, run free!"
        case 15...89:
            return "Medium pollen leves. Wear mask if sensitive, otherwise proceed with caution"
        case 90...1499:
            return "High pollen levels. Definitely wear a mask and proceed with extreme caution or any necessary measures."
        default:
            return "Health warning of emergency conditions. Everyone should avoid all outdoor physical activity."
        }
    }
    
    private func pollenColor(for count: Int) -> Color {
        switch count {
        case 0...14:
            return .green
        case 15...89:
            return .orange
        case 90...1499:
            return .red
        default:
            return .yellow
        }
    }
    
    private func pollenCategory(for count: Int) -> String {
        switch count {
        case 0...14:
            return "Low"
        case 15...89:
            return "Moderate"
        case 90...1499:
            return "High"
        default:
            return "Very High"
        }
    }
    
    private func errorMessage(_ message: String) -> String {
        if message.contains("denied") || vm.locationManager.authorizationStatus == .denied {
            return "Location access denied. Please enable location services in Settings to view air quality data."
        } else if vm.locationManager.authorizationStatus == .restricted {
            return "Location services are restricted on this device."
        } else if message.contains("network") || message.contains("Network") {
            return "Failed to fetch air quality data. Please check your internet connection."
        } else {
            return "Unable to load air quality data. Please try again."
        }
    }
    
    private func fetchData() {
        guard let coordinate = vm.locationManager.location else {
            print("fetchDataIfNeeded called but location is nil")
            return
        }
        print("Fetching real location: \(coordinate.latitude), \(coordinate.longitude)")
        Task {
            await vm.fetchAirQualityData(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}

#Preview("Loading State") {
    DashboardView()
}
