import SwiftUI
import Charts
import RespiratoryKit

/// The main comparison always keeps symptoms immediately beside air and pollen.
struct TrendsPanels: View {
    let data: ChartData
    @Binding var selection: Date?
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Symptoms & surroundings").font(.headline)
                Text("Compare the same dates in each chart.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if data.checkIns.contains(where: { $0.severity != nil }) {
                HistorySymptomsPanel(data: data, selection: $selection)
            } else {
                HistoryMissingSeries(title: "Symptoms", detail: data.checkIns.contains { $0.daytimeSymptoms == true }
                    ? "Symptoms were reported, without severity answers. Inspect a day for details."
                    : "No daytime symptom answers in this period.")
                Button("Add a check-in", systemImage: "plus") { openRoute(.checkIn) }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            Divider()
            if !data.waqi.isEmpty || !data.hourly.isEmpty {
                HistoryAirPanel(data: data, selection: $selection)
            } else {
                HistoryMissingSeries(title: "Air quality", detail: "No saved air readings in this period.")
            }
            Divider()
            if !data.pollen.isEmpty {
                HistoryPollenPanel(data: data, selection: $selection)
            } else {
                HistoryMissingSeries(title: "Pollen", detail: "No saved pollen forecasts in this period.")
            }
            Text("Days that line up don't show that one caused the other.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Inspect a day", systemImage: "calendar") {
                selection = data.days.last?.interval.start
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityHint("Opens day details with previous and next day buttons. You can also select a day on a chart.")
        }
        .airQCard()
    }
}

struct HistoryMissingSeries: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// All charts share a date domain. Missing values are gaps, never zeroes.
struct TrendsPanel<Content: ChartContent>: View {
    let title: String
    let data: ChartData
    @Binding var selection: Date?
    let height: CGFloat
    var showsYAxis = true
    @ChartContentBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    private var axisDates: [Date] {
        guard let last = data.days.indices.last else { return [] }
        return Array(Set([0, last / 3, last * 2 / 3, last])).sorted()
            .map { data.days[$0].interval.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Chart {
                content()
                if let selection {
                    RuleMark(x: .value("Selected", selection))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: data.domain.start...data.domain.end)
            .chartXSelection(value: $selection)
            .chartLegend(.visible)
            .chartXAxis {
                if typeSize.isAccessibilitySize {
                    AxisMarks(values: [data.domain.start, data.domain.end]) { AxisGridLine() }
                } else {
                    AxisMarks(values: axisDates) { mark in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                                       anchor: mark.index == 0 ? .topLeading : mark.index == mark.count - 1 ? .topTrailing : .top,
                                       collisionResolution: .greedy)
                    }
                }
            }
            .chartYAxis {
                if showsYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            }
            .frame(height: typeSize.isAccessibilitySize ? height * 1.6 : height)
            if typeSize.isAccessibilitySize {
                Text("\(data.domain.start.formatted(.dateTime.month(.abbreviated).day())) – \(data.domain.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
