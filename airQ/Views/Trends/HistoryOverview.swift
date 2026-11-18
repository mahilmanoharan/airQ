import SwiftUI
import RespiratoryKit

extension ChartData {
    var hasHistoryContent: Bool {
        !checkIns.isEmpty || !waqi.isEmpty || !hourly.isEmpty || !pollen.isEmpty
            || !context.isEmpty || hasListeningHistory || (airCoverage?.storedHours ?? 0) > 0
    }

    var hasListeningHistory: Bool { hasListeningSessions || hasHourOfDayData }

    var hasMedicationAnswers: Bool {
        checkIns.contains { $0.controllerAdherence != nil || $0.rescueInhalerUses != nil || $0.peakFlowLPM != nil }
    }

    func day(at date: Date) -> Day? {
        // Charts can return the right-hand edge of the plot, which is the end of the last day.
        if date == domain.end { return days.last }
        return days.first { $0.interval.start <= date && date < $0.interval.end }
    }
}

struct HistoryJournal: View {
    let data: ChartData
    let open: (HistoryDetail) -> Void

    var body: some View {
        if let latest = data.checkIns.last {
            VStack(alignment: .leading, spacing: 6) {
                Text("Latest check-in · \(latest.day.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(TrendsLabels.checkInSummary(latest))
                    .font(.title3.weight(.semibold)).fontDesign(.rounded)
                    .accessibilityIdentifier("historyCheckInSummary")
            }
            .airQCard()
        } else {
            HistoryEmptyState(hasHistory: data.hasHistoryContent)
        }

        if data.hasHistoryContent {
            VStack(spacing: 0) {
                row(.day, title: "View a day", symbol: "calendar")
                Divider()
                row(.comparison, title: HistoryDetail.comparison.title, symbol: "chart.xyaxis.line")
                if data.hasListeningHistory {
                    Divider()
                    row(.listening, title: HistoryDetail.listening.title, symbol: "waveform")
                }
            }
            .airQCard()
        }
    }

    private func row(_ destination: HistoryDetail, title: String, symbol: String) -> some View {
        Button { open(destination) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(AirQStyle.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title).fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 48)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HistoryCoverage: View {
    let data: ChartData

    private var airDays: Int {
        Set((data.waqi + data.hourly).map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In these \(data.days.count) days").fontWeight(.semibold)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    counts
                }
                VStack(alignment: .leading, spacing: 6) {
                    counts
                }
            }
            if let coverage = data.airCoverage {
                if coverage.places.count > 1 {
                    Text("Air readings span \(coverage.places.count) saved areas.")
                }
                if coverage.ambiguousHours > 0 {
                    Label("\(coverage.ambiguousHours) hours excluded due to overlapping saved areas", systemImage: "info.circle")
                }
                if coverage.unknownPlaceHours > 0 {
                    Text("\(coverage.unknownPlaceHours) legacy hours have no saved area information.")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var counts: some View {
        Text("\(data.checkIns.count) check-in days")
        Text("\(airDays) AQI days")
        Text("\(Set(data.pollen.map(\.day)).count) pollen days")
    }
}

private struct HistoryEmptyState: View {
    let hasHistory: Bool
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hasHistory ? "No check-ins in this period" : "Your history starts with a day")
                .font(.title3.weight(.semibold)).fontDesign(.rounded)
            Text("Add a check-in to remember how you felt.").foregroundStyle(.secondary)
            Button("Add a check-in", systemImage: "plus") { openRoute(.checkIn) }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .airQCard()
    }
}
