import SwiftUI
import AirQualityKit

enum DashboardMetric: String, CaseIterable, Identifiable {
    case airQuality, pollen

    var id: Self { self }

    var title: String {
        switch self {
        case .airQuality: "Air quality"
        case .pollen: "Pollen"
        }
    }
}

struct DashboardEssentialsView: View {
    let snapshot: AQSnapshot
    let transition: Namespace.ID
    let open: (DashboardMetric) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var savedReading: Bool {
        !snapshot.isFresh(asOf: .now, within: AQSnapshot.freshFor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.locationName)
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(savedReading
                     ? "Last saved \(snapshot.lastUpdated.formatted(date: .abbreviated, time: .shortened))"
                     : "Updated \(snapshot.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if typeSize >= .xxLarge {
                VStack(spacing: 10) {
                    ForEach(DashboardMetric.allCases) { card($0) }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(DashboardMetric.allCases) { card($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(_ metric: DashboardMetric) -> some View {
        let reading = ReadingCardView(metric: metric, snapshot: snapshot)
        return Button { open(metric) } label: {
            reading
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reading.spokenLabel)
        .accessibilityHint("Opens \(metric.title.lowercased()) details")
        .accessibilityIdentifier("todayMetric-\(metric.rawValue)")
        .matchedTransitionSource(id: metric, in: transition)
    }
}
