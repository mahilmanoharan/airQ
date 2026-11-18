import SwiftUI
import RespiratoryKit

struct ReportTimeline: View {
    let report: ClinicianReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly timeline")
                .font(.title2.weight(.semibold)).fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            if report.summary.checkInDays == 0 && report.summary.air.reported == 0 && report.summary.pollenDays == 0 {
                Text("No check-in answers, covered air days or pollen forecasts in this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .airQCard()
            } else {
                Text("Symptoms, waking and rescue inhaler show days out of answers to that question. A dash means unanswered. Air history describes saved areas.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(report.weeks) { ReportWeekRow(week: $0) }
            }
        }
    }
}

private struct ReportWeekRow: View {
    let week: ClinicianReport.Week
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reportDateRange(week.firstDayKey, week.lastDayKey))
                .font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("\(week.checkInDays) of \(week.dayCount) days with check-ins")
                .font(.footnote).foregroundStyle(.secondary)
            Divider()
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { checkInStats }
            } else {
                HStack(alignment: .top, spacing: 12) { checkInStats }
            }
            ReportMetricRow("Peak flow", value: peakFlow)
            ReportMetricRow("Air quality", value: air)
            ReportMetricRow("Pollen forecast", value: pollen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .airQCard()
        .accessibilityIdentifier("reportWeek-\(week.id)")
    }

    private var peakFlow: String {
        guard let readings = week.peakFlow else { return "No readings" }
        let low = readings.lowerBound, high = readings.upperBound
        return low == high ? "\(low) L/min" : "\(low)–\(high) L/min"
    }

    private var air: String {
        guard let peak = week.highestAQI else { return "No covered days" }
        return "Peak US AQI \(peak) · \(week.airDays) of \(week.dayCount) days"
    }

    private var pollen: String {
        guard week.pollenDays > 0 else { return "No forecast days" }
        return "\(week.pollenAtLeastModerateDays) of \(week.pollenDays) days at index \(ClinicianSummary.pollenHighIndex)+"
    }

    @ViewBuilder private var checkInStats: some View {
        checkInStat("Symptoms", answers: week.symptoms)
        checkInStat("Night waking", answers: week.nightWaking)
        checkInStat("Rescue inhaler", answers: week.rescueInhaler)
    }

    private func checkInStat(_ label: String, answers: ClinicianReport.AnsweredDays) -> some View {
        let visibleValue = answers.answered > 0 ? "\(answers.positive)/\(answers.answered)" : "—"
        let spokenValue = answers.answered > 0 ? "\(answers.positive) of \(answers.answered) answered days" : "No answers"
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(visibleValue).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(spokenValue)")
    }
}
