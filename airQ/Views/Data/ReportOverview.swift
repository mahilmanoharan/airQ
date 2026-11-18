import SwiftUI
import RespiratoryKit

struct ReportIntroduction: View {
    let summary: ClinicianSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reportDateRange(summary.firstDayKey, summary.lastDayKey))
                .font(.subheadline).foregroundStyle(.secondary)
            checkInStatement
        }
    }

    private var checkInStatement: Text {
        if summary.checkInDays == 0 {
            Text("No check-ins saved for these dates. Check in to add your symptoms to the report.")
        } else if summary.symptomAnswered == 0 {
            Text("Your check-ins for these dates don’t include daytime symptom answers.")
        } else if summary.symptomDays == 0 {
            Text("You reported no daytime symptoms on the ^[\(summary.symptomAnswered) days](inflect: true) you answered.")
        } else {
            Text("You reported daytime symptoms on \(summary.symptomDays) of the ^[\(summary.symptomAnswered) days](inflect: true) you answered.")
        }
    }
}

func reportDateRange(_ first: String, _ last: String) -> String {
    guard let start = DayKeys.date(first), let end = DayKeys.date(last), start < end else {
        return DayKeys.display(first)
    }
    return (start..<end).formatted(date: .abbreviated, time: .omitted)
}

struct ReportOverview: View {
    let summary: ClinicianSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clinician overview")
                    .font(.title2.weight(.semibold)).fontDesign(.rounded)
                    .accessibilityAddTraits(.isHeader)
                Text(reportDateRange(summary.firstDayKey, summary.lastDayKey))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            ReportMetricRow("Daytime symptoms", value: answeredDays(summary.symptomDays, of: summary.symptomAnswered))
            ReportMetricRow("Night waking", value: answeredDays(summary.nightWakingDays, of: summary.nightWakingAnswered))
            ReportMetricRow("Rescue inhaler", value: rescueValue)
            ReportMetricRow("Peak flow", value: peakFlowValue)
        }
        .airQCard()
    }

    private func answeredDays(_ positive: Int, of answered: Int) -> String {
        answered > 0 ? "\(positive) of \(answered) answered days" : "No answers"
    }

    private var rescueValue: String {
        guard summary.rescueAnswered > 0 else { return "No answers" }
        let total = summary.rescueUses == 1 ? "1 use" : "\(summary.rescueUses) uses"
        return "\(answeredDays(summary.rescueDays, of: summary.rescueAnswered)) · \(total)"
    }

    private var peakFlowValue: String {
        guard let low = summary.peakFlowLowest, let high = summary.peakFlowHighest else { return "No readings" }
        let range = low == high ? String(low) : "\(low)–\(high)"
        let readings = summary.peakFlowReadings == 1 ? "1 reading" : "\(summary.peakFlowReadings) readings"
        return "\(range) L/min · \(readings)"
    }
}

struct ReportCoverage: View {
    let summary: ClinicianSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coverage").font(.headline).accessibilityAddTraits(.isHeader)
            coverageRow("Check-ins", count: summary.checkInDays)
            coverageRow("Air quality", count: summary.air.reported)
            coverageRow("Pollen forecast", count: summary.pollenDays)
            Text("Air counts days with at least \(DailyPeaks.minimumHours) usable hourly readings. Pollen uses the forecast date when available.")
                .font(.footnote).foregroundStyle(.secondary)
            if summary.airCoverage.ambiguousHours > 0 {
                Text("\(summary.airCoverage.ambiguousHours) overlapping hours from different or uncertain areas were excluded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .airQCard()
    }

    private func coverageRow(_ label: String, count: Int) -> some View {
        let value = "\(count) of \(summary.dayCount) days"
        return ReportMetricRow(label, value: value)
            .accessibilityLabel("\(label), \(value)")
            .accessibilityIdentifier("reportCoverage-\(label)")
    }
}

struct ReportMetricRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).foregroundStyle(.secondary)
                    Text(value).monospacedDigit()
                }
            } else {
                LabeledContent(label) {
                    Text(value).foregroundStyle(.primary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
