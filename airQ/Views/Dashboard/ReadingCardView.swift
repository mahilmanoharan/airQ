import SwiftUI
import AirQualityKit

struct ReadingCardView: View {
    let metric: DashboardMetric
    let snapshot: AQSnapshot
    var showsDetailsLink = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { metric == .airQuality ? "Air quality" : "Pollen forecast" }

    private var value: String? {
        switch metric {
        case .airQuality: "\(snapshot.aqi) AQI"
        case .pollen: snapshot.pollenIndex.map { "\($0)/5" }
        }
    }

    private var category: String {
        switch metric {
        case .airQuality: AirQualityPresentation.category(for: snapshot.aqi)
        case .pollen: PollenPresentation.category(for: snapshot.pollenIndex)
        }
    }

    private var levelColor: Color {
        switch metric {
        case .airQuality: AirQualityPresentation.color(for: snapshot.aqi)
        case .pollen: PollenPresentation.color(for: snapshot.pollenIndex)
        }
    }

    private var forecastDay: String? {
        guard metric == .pollen,
              let key = snapshot.pollenTypes?.firstDayKey,
              key != DayKey.local(.now),
              let date = DayKey.date(key) else { return nil }
        return date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())
    }

    private var meaning: String? {
        switch metric {
        case .airQuality:
            switch AirQualityPresentation.band(for: snapshot.aqi).range.lowerBound {
            case 0: "Air pollution poses little or no risk."
            case 51: "People unusually sensitive to air pollution may be affected."
            case 101: "People in sensitive groups should take care outdoors."
            case 151: "Avoid strenuous outdoor activity."
            case 201: "Avoid outdoor activities."
            default: "Avoid all outdoor physical activity."
            }
        case .pollen:
            switch snapshot.pollenIndex {
            case nil: nil
            case 0: "No pollen is forecast."
            case 1, 2: "People sensitive to pollen may still notice symptoms."
            default: "People sensitive to pollen are more likely to notice symptoms."
            }
        }
    }

    var spokenLabel: String {
        let reading: String
        switch metric {
        case .airQuality: reading = "Air quality index \(snapshot.aqi), \(category)"
        case .pollen:
            reading = snapshot.pollenIndex.map { "Pollen forecast \($0) of 5, \(category)" } ?? "Pollen forecast unavailable"
        }
        return [reading, forecastDay, meaning].compactMap { $0 }.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: metric == .airQuality ? "wind" : "leaf.fill")
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
            if let forecastDay {
                Text(forecastDay).font(.caption).foregroundStyle(.secondary)
            }
            Label {
                Text(category).font(.title3.bold()).fontDesign(.rounded)
            } icon: {
                Circle().fill(levelColor).frame(width: 9, height: 9).accessibilityHidden(true)
            }
            if let meaning {
                Text(meaning)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if let value {
                Text(value).font(.subheadline).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)
            }
            if showsDetailsLink {
                Text("See details")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AirQStyle.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background { AirQStyle.tintedSurface(levelColor) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}
