import SwiftUI
import AirQualityKit

/// Tree, grass and weed on Google's 0–5 Universal Pollen Index.
struct PollenBreakdownView: View {
    let pollen: PollenReading
    /// When the forecast was requested: its day 0. Later outlook days count on from here.
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pollen by type").font(.headline).accessibilityAddTraits(.isHeader)
                PollenForecastRow(title: "Tree pollen", index: pollen.treeIndex)
                    .accessibilityIdentifier("pollenType-tree")
                PollenForecastRow(title: "Grass pollen", index: pollen.grassIndex)
                    .accessibilityIdentifier("pollenType-grass")
                PollenForecastRow(title: "Weed pollen", index: pollen.weedIndex)
                    .accessibilityIdentifier("pollenType-weed")
            }
            .dashboardCard()
            if let outlook = pollen.outlook, !outlook.isEmpty {
                PollenOutlookView(pollen: pollen, outlook: outlook, fetchedAt: fetchedAt)
            }
            if let plants = pollen.plants, !plants.isEmpty {
                PollenPlantsRow(plants: plants)
            }
            Text("Google pollen forecast")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct PollenForecastRow: View {
    let title: String
    let index: Int?

    private var category: String { PollenPresentation.category(for: index) }

    var body: some View {
        let color = PollenPresentation.color(for: index)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    name.fixedSize()
                    Spacer(minLength: 0)
                    reading.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    name
                    reading
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(index.map { "\($0) of 5, \(category)" } ?? category)
    }

    private var name: some View { Text(title).font(.body.weight(.semibold)) }

    private var reading: some View {
        Text(index.map { "\(category) · \($0) of 5" } ?? category)
            .font(.body)
    }
}

/// Plants with a forecast value, highest index first. A dashed outline marks out-of-season plants.
private struct PollenPlantsRow: View {
    let plants: [PollenPlant]

    var body: some View {
        DisclosureGroup("Plant details") {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6) {
                    ForEach(plants) { plant in
                        let color = PollenPresentation.color(for: plant.index)
                        let offSeason = plant.inSeason == false
                        Text("\(plant.name) \(plant.index)")
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(offSeason ? 0.06 : 0.15)))
                            .overlay {
                                if offSeason {
                                    Capsule().strokeBorder(.secondary, style: StrokeStyle(dash: [2, 2]))
                                }
                            }
                            .accessibilityLabel(plant.name)
                            .accessibilityValue("\(plant.index) of 5, \(PollenPresentation.category(for: plant.index))"
                                                + (offSeason ? ", out of season" : ""))
                            .accessibilityIdentifier("pollenPlant-\(plant.code)")
                    }
                }
                if plants.contains(where: { $0.inSeason == false }) {
                    Text("Dashed plants are out of season.").font(.footnote)
                }
            }
            .padding(.top, 8)
        }
        .tint(.primary)
        .dashboardCard()
    }
}

/// Each forecast day's highest type index, labelled by Google's own dates when known (else by
/// counting on from the fetch day).
private struct PollenOutlookView: View {
    let pollen: PollenReading
    let outlook: [PollenOutlookDay]
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Forecast by day").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(Array(([pollen.overallIndex] + outlook.map(\.overallIndex)).enumerated()), id: \.offset) { offset, index in
                PollenForecastRow(title: label(offset), index: index)
                    .accessibilityIdentifier("pollenOutlook-\(offset)")
            }
        }
        .dashboardCard()
    }

    private func label(_ offset: Int) -> String {
        if let keys = pollen.dayKeys, keys.indices.contains(offset), let day = DayKey.date(keys[offset]) {
            return day.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day())
        }
        let calendar = Calendar.current
        guard let base = fetchedAt, let date = calendar.date(byAdding: .day, value: offset, to: base) else {
            return "Forecast day \(offset + 1)"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

#Preview {
    PollenBreakdownView(
        pollen: PollenReading(grassIndex: 1, treeIndex: 3, weedIndex: nil,
                              plants: [.init(code: "OAK", name: "Oak", index: 3), .init(code: "RAGWEED", name: "Ragweed", index: 1)],
                              outlook: [.init(grassIndex: 1, treeIndex: 2, weedIndex: nil), .init(grassIndex: nil, treeIndex: 4, weedIndex: 0)]),
        fetchedAt: .now)
        .padding()
}
