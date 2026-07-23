import SwiftUI
import CoreLocation
import AirQualityKit

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
        case .loaded(let snapshot):
            loadedView(snapshot: snapshot)
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

    private func loadedView(snapshot: AQSnapshot) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Text(snapshot.locationName)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 32) {
                AQICardView(aqi: snapshot.aqi)
                PollenCardView(index: snapshot.pollenIndex)
            }

            if let dominantPollutant = snapshot.dominantPollutant {
                Text("Primary Pollutant: \(dominantPollutant.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AnalysisCardView(
                title: "AQI analysis",
                message: AirQualityPresentation.guidance(for: snapshot.aqi),
                tintColor: AirQualityPresentation.color(for: snapshot.aqi)
            )

            AnalysisCardView(
                title: "Pollen analysis",
                message: PollenPresentation.guidance(for: snapshot.pollenIndex),
                tintColor: PollenPresentation.color(for: snapshot.pollenIndex)
            )

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
        case .loaded(let snapshot):
            return AirQualityPresentation.color(for: snapshot.aqi).opacity(0.05)
        default:
            return Color(.systemBackground)
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
