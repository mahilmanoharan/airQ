import SwiftUI
import RespiratoryKit

/// Stays above the tab bar while inspecting, including when the selected chart scrolls.
struct TrendsSelectionSummary: View {
    let data: ChartData
    @Binding var selection: Date?
    var close: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var index: Int? {
        guard let selection, let day = data.day(at: selection) else { return nil }
        return data.days.firstIndex { $0.dayKey == day.dayKey }
    }

    var body: some View {
        if let index, let first = data.days.first, let last = data.days.last {
            let day = data.days[index]
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        datePicker(for: day, in: first.interval.start...last.interval.start)
                        Spacer(minLength: 0)
                        navigation(for: index)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        datePicker(for: day, in: first.interval.start...last.interval.start)
                        navigation(for: index)
                    }
                }
                HistoryDayValues(data: data, day: day, stacked: typeSize.isAccessibilitySize)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func datePicker(for day: ChartData.Day, in range: ClosedRange<Date>) -> some View {
        DatePicker("Choose a date", selection: Binding(get: { day.interval.start }, set: { selection = $0 }),
                   in: range, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .frame(minHeight: 44)
            .accessibilityIdentifier("historyDayDate")
    }

    private func navigation(for index: Int) -> some View {
        HStack(spacing: 0) {
            dayButton("Previous day", symbol: "chevron.backward") { move(to: index - 1) }
                .disabled(index == 0)
            dayButton("Next day", symbol: "chevron.forward") { move(to: index + 1) }
                .disabled(index == data.days.count - 1)
            if let close {
                dayButton("Close day details", symbol: "xmark", action: close)
            }
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
}

private struct HistoryDayValues: View {
    let data: ChartData
    let day: ChartData.Day
    let stacked: Bool

    private var checkIn: ChartData.CheckInPoint? {
        data.checkIns.first { $0.day == day.interval.start }
    }

    var body: some View {
        let checkIn = checkIn
        let inhaler = checkIn?.rescueInhalerUses.map { $0 == 1 ? "1 use" : "\($0) uses" }
            ?? (checkIn == nil ? "No check-in" : "Not answered")
        let pollen = data.pollen.lazy.filter { $0.day == day.interval.start }.map(\.upi).max()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: stacked ? 1 : 2)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            metric("Symptoms", id: "symptoms", value: symptomsText(for: checkIn))
            metric("Rescue inhaler", id: "rescue", value: inhaler)
            metric("Highest saved AQI", id: "air", value: airQuality())
            metric("Pollen forecast", id: "pollen", value: pollen.map { "\($0) of 5" } ?? "No pollen forecast")
        }
    }

    private func metric(_ title: String, id: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier("historyDay-\(id)")
    }

    private func symptomsText(for point: ChartData.CheckInPoint?) -> String {
        guard let point else { return "No check-in" }
        let daytime: String
        switch point.severity {
        case 0?: daytime = "No daytime symptoms"
        case let severity?:
            let label = CheckInQuestionSet.Severity(rawValue: severity).map(CheckInLabels.severity) ?? "\(severity) of 3"
            daytime = "\(label) daytime symptoms"
        case nil:
            daytime = point.daytimeSymptoms == true ? "Daytime symptoms, severity unanswered" : "Daytime symptoms unanswered"
        }
        switch point.nightWaking {
        case true?: return "\(daytime) · Woke last night"
        case false?: return daytime
        case nil: return "\(daytime) · Night waking unanswered"
        }
    }

    private func airQuality() -> String {
        var parts: [String] = []
        if let hourly = peakAQI(in: data.hourly) {
            parts.append("Google \(hourly)")
        }
        if let station = peakAQI(in: data.waqi) {
            parts.append("WAQI \(station)")
        }
        return parts.isEmpty ? "No saved AQI" : parts.joined(separator: " · ")
    }

    private func peakAQI(in readings: [EnvironmentSeries.AQIPoint]) -> Int? {
        readings.lazy.filter { day.interval.start <= $0.date && $0.date < day.interval.end }.map(\.value).max()
    }
}
