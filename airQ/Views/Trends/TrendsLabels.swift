import SwiftUI
import RespiratoryKit

struct TrendsLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Missing answers and readings stay as gaps. Opening airQ does not mean a check-in was completed.")
            Text("Station dots are WAQI readings when measured; hourly dots are Google's AQI. These describe saved places, not your personal exposure. Pollen is a forecast for the date shown.")
            Text("Sounds depend on your listening sensitivity and cover only recorded listening time. Life events are entries you saved; faded bars are ongoing.")
        }
        .font(.footnote).foregroundStyle(.secondary)
    }
}

enum TrendsLabels {
    static func pollen(_ code: String) -> String {
        switch code {
        case "GRASS": "Grass"
        case "TREE": "Tree"
        case "WEED": "Weed"
        default: code.capitalized
        }
    }

    static func contextValue(_ span: ChartData.ContextSpan) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        let start = span.originalStartDayKey.map { DayKeys.display($0, style: style) }
            ?? span.start.formatted(date: .abbreviated, time: .omitted)
        let end = span.originalEndDayKey.map { DayKeys.display($0, style: style) }
            ?? span.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
        let range = "\(start) to \(span.isOngoing ? "ongoing" : end)"
        return span.note.isEmpty ? range : "\(range). \(span.note)"
    }
}
