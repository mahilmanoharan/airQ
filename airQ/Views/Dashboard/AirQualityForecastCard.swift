import SwiftUI
import AirQualityKit

/// WAQI's daily forecast: each day's highest forecast pollutant sub-index, its AQI band, and the
/// day's peak UV index. The forecast came with the last reading, so it costs no extra request.
struct AirQualityForecastCard: View {
    let days: [AirQualityForecastDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Forecast").font(.headline)
            ForEach(days) { day in
                ForecastRow(day: day)
                if day.id != days.last?.id { Divider() }
            }
            Text("Station forecast: highest daily pollutant sub-index on the AQI scale.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }
}

private struct ForecastRow: View {
    let day: AirQualityForecastDay
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 12) {
            Text(dayLabel)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 76, alignment: .leading)
            if let peak = day.peak {
                let color = AirQualityPresentation.color(for: peak.subIndex)
                Text("\(peak.subIndex)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(minWidth: 40)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.2)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(AirQualityPresentation.category(for: peak.subIndex))
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(StationConditions.displayName(for: peak.code))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let uv = day.uvIndex {
                Label("UV \(uv.max)", systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var dayLabel: String { DayKey.label(day.day, relativeTo: .now, calendar: calendar) }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let peak = day.peak {
            parts.append("Peak \(StationConditions.displayName(for: peak.code)) \(peak.subIndex), "
                         + AirQualityPresentation.category(for: peak.subIndex))
        }
        if let uv = day.uvIndex { parts.append("UV index up to \(uv.max)") }
        return parts.isEmpty ? "No forecast" : parts.joined(separator: ", ")
    }
}

#Preview {
    AirQualityForecastCard(days: [
        .init(day: "2026-09-28", pollutants: ["pm25": .init(min: 32, average: 36, max: 51)], uvIndex: .init(min: 0, average: 1, max: 6)),
        .init(day: "2026-09-29", pollutants: ["pm25": .init(min: 22, average: 33, max: 68)], uvIndex: .init(min: 0, average: 1, max: 7)),
        .init(day: "2026-09-30", pollutants: ["pm10": .init(min: 6, average: 8, max: 15)], uvIndex: nil),
    ])
    .padding()
}
