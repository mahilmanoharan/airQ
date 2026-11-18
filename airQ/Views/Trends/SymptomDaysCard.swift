import SwiftUI
import AirQualityKit
import RespiratoryKit

/// "Were my symptom days the bad-air days?" as plain counts for the span on screen. It draws no conclusion:
/// the numbers sit side by side and the footnote says what they can't show.
struct SymptomDaysCard: View {
    let table: SymptomDaysByLevel
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your symptom days by air and pollen").font(.headline)
            if table.isEmpty {
                Text("Answer \"Any breathing or allergy symptoms today?\" in your check-ins, and this shows how many of those days had symptoms at each air-quality and pollen level.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Go to Check-in", systemImage: "checklist") { openRoute(.checkIn) }
                    .buttonStyle(.borderedProminent)
            } else {
                if !table.air.isEmpty {
                    Text("Air quality").font(.subheadline.weight(.semibold))
                    ForEach(table.air, id: \.level) { row in
                        SymptomDaysRow(level: Self.air(row.level), row: (row.days, row.symptomDays))
                    }
                }
                if !table.pollen.isEmpty {
                    Text("Pollen").font(.subheadline.weight(.semibold))
                    ForEach(table.pollen, id: \.level) { row in
                        SymptomDaysRow(level: "\(row.level) · \(PollenPresentation.category(for: row.level))",
                                       row: (row.days, row.symptomDays))
                    }
                }
                Text("Counts of your checked-in days in this span. A few days can't show a pattern, and days that line up don't show that one causes the other. Air uses days with at least 18 hours of Google's index; pollen is the day's forecast.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .airQCard()
    }

    static func air(_ band: AirQualityBand) -> String {
        switch band {
        case .good: "Good (0–50)"
        case .moderate: "Moderate (51–100)"
        case .sensitive: "Unhealthy for sensitive groups (101–150)"
        case .unhealthy: "Unhealthy or worse (151+)"
        }
    }
}

private struct SymptomDaysRow: View {
    let level: String
    let row: (days: Int, symptomDays: Int)

    var body: some View {
        LabeledContent(level) {
            Text("symptoms on \(row.symptomDays) of \(row.days) \(row.days == 1 ? "day" : "days")")
                .monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
