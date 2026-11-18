import SwiftUI
import AirQualityKit
import RespiratoryKit

/// How the last 30 days went at this place: each day counted once, in the AQI category of its
/// highest hourly value. Drawn from stored hourly history only (no requests). It appears once
/// there is at least one full day to report. Like the 48-hour card it always renders a card, so its
/// load task always has a view to attach to (a `.task` on an empty `Group` never runs).
struct MonthAirQualityCard: View {
    @State private var model: MonthAirQualityViewModel
    let refreshKey: Int

    init(records: RecordStore, place: RecordPlace?, refreshKey: Int) {
        _model = State(initialValue: MonthAirQualityViewModel(records: records, place: place))
        self.refreshKey = refreshKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.errorMessage {
                Text("Past 30 days").font(.headline)
                Text(message).font(.caption).foregroundStyle(.red)
            } else if model.hasLoaded, !model.isEmpty {
                MonthSummary(days: model.days, partialDays: model.partialDays)
            } else if model.hasLoaded {
                Text("Past 30 days").font(.headline)
                Text("A summary of the month appears once airQ has stored at least one full day of hourly history (it collects it at most once a day).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Past 30 days").font(.headline)
                ProgressView().frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .dashboardCard()
        .task(id: refreshKey) { await model.load() }
    }
}

private struct MonthSummary: View {
    let days: [DayPeak]
    let partialDays: Int

    /// Days per AQI category, in category order, for the categories that occurred.
    private var counts: [(band: AirQualityPresentation.Band, days: Int)] {
        AirQualityPresentation.bands.compactMap { band in
            let matching = days.count { AirQualityPresentation.band(for: $0.peak).category == band.category }
            return matching > 0 ? (band, matching) : nil
        }
    }

    private var summaryText: String {
        counts.map { "\($0.days) \($0.days == 1 ? "day" : "days") \($0.band.category)" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past 30 days").font(.headline)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(counts, id: \.band.category) { entry in
                        Rectangle()
                            .fill(entry.band.color)
                            .frame(width: max(2, proxy.size.width * CGFloat(entry.days) / CGFloat(days.count)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 14)
            ForEach(counts, id: \.band.category) { entry in
                HStack {
                    Circle().fill(entry.band.color).frame(width: 10, height: 10)
                    Text(entry.band.category).font(.subheadline)
                    Spacer()
                    Text("\(entry.days) \(entry.days == 1 ? "day" : "days")").font(.subheadline.monospacedDigit())
                }
            }
            Text(footnote).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Past 30 days")
        .accessibilityValue(summaryText)
    }

    private var footnote: String {
        var text = "Each day is counted in the category of its highest hourly value (Google's US EPA index), from \(days.count) day\(days.count == 1 ? "" : "s") of stored history."
        if partialDays > 0 {
            text += " \(partialDays) day\(partialDays == 1 ? "" : "s") with too little history \(partialDays == 1 ? "is" : "are") left out."
        }
        return text
    }
}
