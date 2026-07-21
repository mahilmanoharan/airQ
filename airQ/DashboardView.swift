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
                AQICardView(aqi: data.data.aqi)

                if let totalPollen = totalPollenCount(from: pollen) {
                    PollenCardView(count: totalPollen)
                }
            }

            if let dominentpol = data.data.dominentpol {
                Text("Primary Pollutant: \(dominentpol.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AnalysisCardView(
                title: "AQI analysis",
                message: AirQualityPresentation.guidance(for: data.data.aqi),
                tintColor: AirQualityPresentation.color(for: data.data.aqi)
            )

            if let totalPollen = totalPollenCount(from: pollen) {
                AnalysisCardView(
                    title: "Pollen analysis",
                    message: PollenPresentation.guidance(for: totalPollen),
                    tintColor: PollenPresentation.color(for: totalPollen)
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
            return AirQualityPresentation.color(for: data.data.aqi).opacity(0.05)
        default:
            return Color(.systemBackground)
        }
    }

    private func totalPollenCount(from pollen: Pollen?) -> Int? {
        guard let firstDatum = pollen?.data.first else { return nil }
        return firstDatum.count.grassPollen + firstDatum.count.treePollen + firstDatum.count.weedPollen
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
