import SwiftUI
import RespiratoryKit

/// Stays above the tab bar while inspecting, including when the selected chart scrolls.
struct TrendsSelectionSummary: View {
    let data: ChartData
    @Binding var selection: Date?

    private var index: Int? {
        selection.flatMap { selected in
            data.days.firstIndex { $0.interval.start <= selected && selected < $0.interval.end }
        }
    }

    var body: some View {
        if let index {
            let day = data.days[index]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(DayKeys.display(day.dayKey, style: .dateTime.month(.abbreviated).day()))
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    dayButton("Previous day", symbol: "chevron.left") { move(to: index - 1) }
                        .disabled(index == 0)
                    dayButton("Next day", symbol: "chevron.right") { move(to: index + 1) }
                        .disabled(index == data.days.count - 1)
                    dayButton("Close day details", symbol: "xmark") { selection = nil }
                }
                Text(symptomSummary(day)).font(.subheadline.weight(.medium))
                Text(environmentSummary(day)).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func dayButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func move(to index: Int) {
        guard data.days.indices.contains(index) else { return }
        selection = data.days[index].interval.start
    }

    private func symptomSummary(_ day: ChartData.Day) -> String {
        guard let point = data.checkIns.first(where: { $0.day == day.interval.start }) else {
            return "No check-in recorded"
        }
        let symptoms: String
        switch point.severity {
        case 0?: symptoms = "No daytime symptoms"
        case let severity?: symptoms = "Daytime symptoms: \(severity) of 3"
        case nil: symptoms = point.daytimeSymptoms == true ? "Daytime symptoms; severity not answered" : "Daytime symptoms not answered"
        }
        return point.nightWaking == true ? "\(symptoms) · Woke at night" : symptoms
    }

    private func environmentSummary(_ day: ChartData.Day) -> String {
        let contains: (Date) -> Bool = { day.interval.start <= $0 && $0 < day.interval.end }
        var parts: [String] = []
        if let peak = data.hourly.filter({ contains($0.date) }).map(\.value).max() {
            parts.append("Hourly AQI up to \(peak)")
        }
        if let peak = data.waqi.filter({ contains($0.date) }).map(\.value).max() {
            parts.append("Station AQI up to \(peak)")
        }
        if parts.isEmpty { parts.append("No air reading") }
        if let pollen = data.pollen.filter({ $0.day == day.interval.start }).map(\.upi).max() {
            parts.append("Pollen up to \(pollen) of 5")
        } else { parts.append("No pollen forecast") }
        return parts.joined(separator: " · ")
    }
}
