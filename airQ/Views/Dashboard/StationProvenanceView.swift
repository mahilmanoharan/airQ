import SwiftUI
import AirQualityKit

/// Which station measured the AQI, how far away it is, and when it measured. An old observation
/// is called out, because WAQI serves a station's latest value however old it is.
struct StationProvenanceView: View {
    let station: StationInfo
    /// Where the device was when it asked.
    let deviceCoordinate: GeoCoordinate?
    let fetchedAt: Date
    @State private var showsMap = false

    var body: some View {
        VStack(spacing: 4) {
            if let stationCoordinate = station.coordinate {
                Button { showsMap = true } label: {
                    Label(details, systemImage: "map")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint("Shows the station on a map")
                .sheet(isPresented: $showsMap) {
                    StationMapSheet(station: station, stationCoordinate: stationCoordinate, deviceCoordinate: deviceCoordinate)
                }
            } else {
                Label(details, systemImage: "sensor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let age = station.observationAge(at: fetchedAt), age >= StationInfo.staleObservationAge {
                Label("This station's latest value is \(Self.hours(age)) old.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var details: String {
        var parts = [station.name.isEmpty ? "Monitoring station" : station.name]
        if let meters = station.distance(from: deviceCoordinate) {
            parts.append(Measurement(value: meters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road)) + " away")
        }
        if let observedAt = station.observedAt {
            parts.append("measured \(observedAt.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private static func hours(_ age: TimeInterval) -> String {
        Duration.seconds(age).formatted(.units(allowed: [.days, .hours], width: .wide, maximumUnitCount: 1))
    }
}
