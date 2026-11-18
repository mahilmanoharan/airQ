import SwiftUI
import AirQualityKit

/// A hero card on the dashboard: the AQI or the pollen level.
struct ReadingCardView: View {
    let value: Int?
    let category: String
    let color: Color
    let caption: String
    let spokenLabel: String

    /// Scales with Dynamic Type from a 72 pt base.
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 48.0

    static func aqi(_ aqi: Int) -> ReadingCardView {
        let category = AirQualityPresentation.category(for: aqi)
        return ReadingCardView(value: aqi, category: category, color: AirQualityPresentation.color(for: aqi),
                               caption: "Air quality (AQI)", spokenLabel: "Air quality index \(aqi), \(category)")
    }

    static func pollen(_ index: Int?) -> ReadingCardView {
        let category = PollenPresentation.category(for: index)
        return ReadingCardView(value: index, category: category, color: PollenPresentation.color(for: index),
                               caption: "Pollen (0–5)",
                               spokenLabel: index.map { "Pollen level \($0) of 5, \(category)" } ?? "Pollen unavailable")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: valueSize, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                // Primary text colour for contrast; the level's colour is the bar below (and the card tint).
                .foregroundStyle(.primary)

            Capsule()
                .fill(color)
                .frame(width: 56, height: 8)
                .accessibilityHidden(true)

            // The word carries the meaning (colour alone can't): large, and in the primary text colour.
            Text(category)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .airQCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}

#Preview {
    HStack { ReadingCardView.aqi(42); ReadingCardView.pollen(3) }
}
