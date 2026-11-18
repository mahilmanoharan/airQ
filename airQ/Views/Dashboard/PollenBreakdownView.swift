import SwiftUI
import AirQualityKit

/// Tree, grass and weed on Google's 0–5 Universal Pollen Index. A missing type shows "—",
/// never zero: the forecast had no value for it.
struct PollenBreakdownView: View {
    let pollen: PollenReading
    /// When the forecast was requested: its day 0. Later outlook days count on from here.
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pollen by type").font(.headline)
            if let first = pollen.firstDayKey, first != DayKey.local(.now), let date = DayKey.date(first) {
                // Google dates its forecast in UTC, so an evening request can already return tomorrow.
                Text("Google's forecast for \(date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                PollenTypeTile(name: "Tree", systemImage: "tree", index: pollen.treeIndex)
                PollenTypeTile(name: "Grass", systemImage: "leaf", index: pollen.grassIndex)
                PollenTypeTile(name: "Weed", systemImage: "camera.macro", index: pollen.weedIndex)
            }
            if let plants = pollen.plants, !plants.isEmpty {
                PollenPlantsRow(plants: plants)
            }
            if let outlook = pollen.outlook, !outlook.isEmpty {
                PollenOutlookRow(pollen: pollen, outlook: outlook, fetchedAt: fetchedAt)
            }
            Text(pollen.plants?.contains { $0.inSeason == false } == true
                 ? "Google daily forecast, not a measurement. Dashed plants are out of season."
                 : "Google daily forecast, not a measurement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }
}

private struct PollenTypeTile: View {
    let name: String
    let systemImage: String
    let index: Int?

    var body: some View {
        let color = PollenPresentation.color(for: index)
        VStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(index.map(String.init) ?? "—").font(.title2.weight(.bold)).foregroundStyle(color)
            Text(name).font(.caption.weight(.medium))
            Text(PollenPresentation.category(for: index))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) pollen")
        .accessibilityValue(index.map { "\($0) of 5, \(PollenPresentation.category(for: $0))" } ?? "Unavailable")
    }
}

/// Plants with a value, highest first, as wrapping chips. Off-season plants are dimmed, not hidden:
/// Google can still forecast a value for them.
private struct PollenPlantsRow: View {
    let plants: [PollenPlant]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plants").font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 6) {
                ForEach(plants) { plant in
                    let color = PollenPresentation.color(for: plant.index)
                    let offSeason = plant.inSeason == false
                    Text("\(plant.name) \(plant.index)")
                        .font(.caption)
                        .foregroundStyle(offSeason ? .secondary : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(offSeason ? 0.06 : 0.15)))
                        .overlay { if offSeason { Capsule().strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(dash: [2, 2])) } }
                        .accessibilityLabel(plant.name)
                        .accessibilityValue("\(plant.index) of 5, \(PollenPresentation.category(for: plant.index))"
                                            + (offSeason ? ", out of season" : ""))
                }
            }
        }
    }
}

/// Each forecast day's highest type index, labelled by Google's own dates when known (else by
/// counting on from the fetch day).
private struct PollenOutlookRow: View {
    let pollen: PollenReading
    let outlook: [PollenOutlookDay]
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next days").font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(Array(([pollen.overallIndex] + outlook.map(\.overallIndex)).enumerated()), id: \.offset) { offset, index in
                    let color = PollenPresentation.color(for: index)
                    VStack(spacing: 2) {
                        Text(label(offset)).font(.caption2).foregroundStyle(.secondary)
                        Text(index.map(String.init) ?? "—").font(.subheadline.weight(.bold)).foregroundStyle(color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(offset))
                    .accessibilityValue(index.map { "\($0) of 5, \(PollenPresentation.category(for: $0))" } ?? "No forecast")
                }
            }
        }
    }

    private func label(_ offset: Int) -> String {
        if let keys = pollen.dayKeys, keys.indices.contains(offset) {
            return DayKey.label(keys[offset], relativeTo: .now)
        }
        let calendar = Calendar.current
        guard let base = fetchedAt, let date = calendar.date(byAdding: .day, value: offset, to: base) else {
            return offset == 0 ? "Today" : "+\(offset)d"
        }
        return DayKey.label(DayKey.local(date, in: calendar), relativeTo: .now, calendar: calendar)
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
