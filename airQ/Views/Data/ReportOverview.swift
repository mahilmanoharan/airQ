import SwiftUI
import RespiratoryKit

struct ReportOverview: View {
    let summary: ClinicianSummary
    let periodTitle: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(periodTitle).font(.title2.weight(.semibold)).fontDesign(.rounded)
                Text("\(summary.firstDayKey) – \(summary.lastDayKey)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text("Coverage").font(.headline)
            coverageRow("Check-ins", count: summary.checkInDays)
            coverageRow("Air quality", count: summary.air.reported)
            coverageRow("Pollen forecast", count: summary.pollenDays)
            Text("Air coverage counts days with at least 18 stored hours. Days without a check-in are unknown.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .airQCard()
    }

    private func coverageRow(_ label: String, count: Int) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(count) of \(summary.dayCount) days").monospacedDigit()
                }
            } else {
                LabeledContent(label) {
                    Text("\(count) of \(summary.dayCount) days")
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(count) of \(summary.dayCount) days")
        .accessibilityIdentifier("reportCoverage-\(label)")
    }
}
