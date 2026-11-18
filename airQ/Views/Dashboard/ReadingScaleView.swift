import SwiftUI
import AirQualityKit

struct ReadingScaleView: View {
    let metric: DashboardMetric
    let snapshot: AQSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(metric == .airQuality ? "AQI scale" : "Pollen scale")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            switch metric {
            case .airQuality:
                ForEach(AirQualityPresentation.bands, id: \.category) { band in
                    row(band.category, value: Self.range(band.range), color: band.color,
                        isCurrent: band.range.contains(snapshot.aqi))
                }
                Text("Higher AQI means more air pollution. This reading comes from a monitoring station.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .pollen:
                ForEach(0...5, id: \.self) { level in
                    row(PollenPresentation.category(for: level), value: String(level),
                        color: PollenPresentation.color(for: level), isCurrent: snapshot.pollenIndex == level)
                }
                Text("Google forecasts pollen on a scale from 0 to 5.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .airQCard()
    }

    private func row(_ title: String, value: String, color: Color, isCurrent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline)
                if isCurrent {
                    Text(metric == .airQuality ? "Your reading" : "Your forecast")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(value).font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(isCurrent ? ", selected level" : "")")
    }

    private static func range(_ range: ClosedRange<Int>) -> String {
        range.upperBound == .max ? "\(range.lowerBound)+" : "\(range.lowerBound)–\(range.upperBound)"
    }
}
