import SwiftUI
import RespiratoryKit

/// Uses the same date and readings in the full inspector and the chart's compact summary.
struct TrendsSelectionSummary: View {
    enum Presentation {
        case day
        case chart(close: () -> Void)
    }

    let data: ChartData
    @Binding var selection: Date?
    let presentation: Presentation
    @Environment(\.dynamicTypeSize) private var typeSize

    private var index: Int? {
        guard let selection, let day = data.day(at: selection) else { return nil }
        return data.days.firstIndex { $0.dayKey == day.dayKey }
    }

    var body: some View {
        if let index, let first = data.days.first, let last = data.days.last {
            let day = data.days[index]
            let range = first.interval.start...last.interval.start
            switch presentation {
            case .day:
                dayPage(day: day, index: index, range: range)
            case .chart(let close):
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            datePicker(for: day, in: range)
                            Spacer(minLength: 0)
                            chartNavigation(for: index, close: close)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            datePicker(for: day, in: range)
                            chartNavigation(for: index, close: close)
                        }
                    }
                    HistoryDayValues(data: data, day: day, stacked: typeSize.isAccessibilitySize, showsCards: false)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func dayPage(day: ChartData.Day, index: Int, range: ClosedRange<Date>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DayKeys.display(day.dayKey, style: .dateTime.weekday(.wide).month(.wide).day()))
                        .font(.title.bold()).fontDesign(.rounded)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("historySelectedDay")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { datePickerRow(for: day, in: range) }
                        VStack(alignment: .leading, spacing: 0) { datePickerRow(for: day, in: range) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { AirQStyle.tintedSurface(AirQStyle.accent) }
                HistoryDayValues(data: data, day: day, stacked: typeSize.isAccessibilitySize, showsCards: true)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AirQStyle.atmosphere }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                dayButton("Previous day", symbol: "chevron.backward", labeled: true) { move(to: index - 1) }
                    .disabled(index == 0)
                dayButton("Next day", symbol: "chevron.forward", labeled: true) { move(to: index + 1) }
                    .disabled(index == data.days.count - 1)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .airQActionBar()
        }
    }

    @ViewBuilder private func datePickerRow(for day: ChartData.Day, in range: ClosedRange<Date>) -> some View {
        Text("Jump to date").font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
        datePicker(for: day, in: range)
    }

    private func datePicker(for day: ChartData.Day, in range: ClosedRange<Date>) -> some View {
        DatePicker("Choose a date", selection: Binding(get: { day.interval.start }, set: { selection = $0 }),
                   in: range, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .frame(minHeight: 44)
            .accessibilityIdentifier("historyDayDate")
    }

    private func chartNavigation(for index: Int, close: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            dayButton("Previous day", symbol: "chevron.backward") { move(to: index - 1) }
                .disabled(index == 0)
            dayButton("Next day", symbol: "chevron.forward") { move(to: index + 1) }
                .disabled(index == data.days.count - 1)
            dayButton("Close day details", symbol: "xmark", action: close)
        }
    }

    private func dayButton(_ label: String, symbol: String, labeled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if labeled {
                Label(label, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 38)
            } else {
                Image(systemName: symbol).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
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
    let showsCards: Bool

    private var checkIn: ChartData.CheckInPoint? {
        data.checkIns.first { $0.day == day.interval.start }
    }

    var body: some View {
        let checkIn = checkIn
        let inhaler = checkIn?.rescueInhalerUses.map { $0 == 1 ? "1 use" : "\($0) uses" }
            ?? (checkIn == nil ? "No check-in" : "Not answered")
        let pollen = data.pollen.lazy.filter { $0.day == day.interval.start }.map(\.upi).max()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: stacked ? 1 : 2)
        LazyVGrid(columns: columns, alignment: .leading, spacing: showsCards ? 12 : 8) {
            metric("Symptoms", id: "symptoms", symbol: "heart.text.clipboard", value: symptomsText(for: checkIn))
            metric("Rescue inhaler", id: "rescue", symbol: "cross.case", value: inhaler)
            metric("Highest saved AQI", id: "air", symbol: "wind", value: airQuality())
            metric("Pollen forecast", id: "pollen", symbol: "leaf", value: pollen.map { "\($0) of 5" } ?? "No pollen forecast")
        }
    }

    private func metric(_ title: String, id: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: showsCards ? 6 : 2) {
            if showsCards {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(showsCards ? .body : .subheadline.weight(.medium))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(showsCards ? 14 : 0)
        .background {
            if showsCards {
                RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground))
            }
        }
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
