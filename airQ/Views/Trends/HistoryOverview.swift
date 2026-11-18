import SwiftUI
import RespiratoryKit

extension ChartData {
    var hasHistoryContent: Bool {
        !checkIns.isEmpty || !waqi.isEmpty || !hourly.isEmpty || !pollen.isEmpty
            || !context.isEmpty || hasHourOfDayData || (airCoverage?.storedHours ?? 0) > 0
    }

    var hasMedicationAnswers: Bool {
        checkIns.contains { $0.controllerAdherence != nil || $0.rescueInhalerUses != nil || $0.peakFlowLPM != nil }
    }
}

struct HistoryCoverageCard: View {
    let data: ChartData
    @Environment(\.dynamicTypeSize) private var typeSize

    private var airDays: Int {
        Set((data.waqi + data.hourly).map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In these \(data.days.count) days").font(.headline)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { counts }
            } else {
                HStack(alignment: .top, spacing: 16) { counts }
            }
            Text("Days without a check-in are unknown, not symptom-free.")
                .font(.footnote).foregroundStyle(.secondary)
            if let coverage = data.airCoverage {
                if coverage.places.count > 1 {
                    Text("Air history includes \(coverage.places.count) saved areas, not a record of where you were.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if coverage.ambiguousHours > 0 {
                    Label("\(coverage.ambiguousHours) overlapping hours left out", systemImage: "info.circle")
                        .font(.footnote.weight(.semibold))
                    Text("Different saved areas have readings for the same hour. Those hours aren't combined in charts or reports.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if coverage.unknownPlaceHours > 0 {
                    Text("\(coverage.unknownPlaceHours) legacy hours have no saved area information.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .airQCard()
    }

    @ViewBuilder private var counts: some View {
        count(data.checkIns.count, label: "check-in days")
        count(airDays, label: "days with air readings")
        count(Set(data.pollen.map(\.day)).count, label: "days with pollen")
    }

    private func count(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.title2.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
            Text(label).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HistoryEmptyState: View {
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle).foregroundStyle(AirQStyle.accent).accessibilityHidden(true)
            Text("Your history starts with a day")
                .font(.title2.weight(.semibold)).fontDesign(.rounded)
            Text("Add a check-in to remember how you felt. As readings are saved, you'll see symptoms beside air quality and pollen here.")
                .foregroundStyle(.secondary)
            Text("Nothing saved in this period yet. You can also choose a longer period above.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Add a check-in", systemImage: "plus") { openRoute(.checkIn) }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .airQCard()
    }
}
