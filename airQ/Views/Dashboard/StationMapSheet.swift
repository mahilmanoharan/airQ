import SwiftUI
import MapKit
import AirQualityKit

/// Where the reading comes from: the device's queried location and the WAQI station, with the
/// straight-line distance between them. Drawn with MapKit on the device; nothing is sent anywhere.
struct StationMapSheet: View {
    let station: StationInfo
    let stationCoordinate: GeoCoordinate
    let deviceCoordinate: GeoCoordinate?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(initialPosition: .rect(Self.region(station: stationCoordinate, device: deviceCoordinate))) {
                    Marker(station.name.isEmpty ? "Station" : station.name, systemImage: "sensor",
                           coordinate: Self.clLocation(stationCoordinate))
                        .tint(.orange)
                    if let deviceCoordinate {
                        Marker("You", systemImage: "location.fill", coordinate: Self.clLocation(deviceCoordinate))
                            .tint(.blue)
                        MapPolyline(coordinates: [Self.clLocation(deviceCoordinate), Self.clLocation(stationCoordinate)])
                            .stroke(.secondary, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .mapControls { MapScaleView() }
                .accessibilityLabel("Map of your location and the monitoring station")
                StationMapCaption(station: station, deviceCoordinate: deviceCoordinate)
            }
            .navigationTitle("Monitoring station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    static func clLocation(_ coordinate: GeoCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Frames both points with a margin; a single point gets a ~2 km view.
    static func region(station: GeoCoordinate, device: GeoCoordinate?) -> MKMapRect {
        let points = [station, device].compactMap(\.self).map { MKMapPoint(clLocation($0)) }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        let span = max(maxX - minX, maxY - minY, MKMapPointsPerMeterAtLatitude(station.latitude) * 2_000)
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
        let padded = span * 1.6
        return MKMapRect(x: centerX - padded / 2, y: centerY - padded / 2, width: padded, height: padded)
    }
}

private struct StationMapCaption: View {
    let station: StationInfo
    let deviceCoordinate: GeoCoordinate?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(station.name.isEmpty ? "Monitoring station" : station.name).font(.subheadline.weight(.semibold))
            if let meters = station.distance(from: deviceCoordinate) {
                Text("\(Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .wide, usage: .road))) from where airQ last checked")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("The AQI is this station's reading, not a measurement at your exact location.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
