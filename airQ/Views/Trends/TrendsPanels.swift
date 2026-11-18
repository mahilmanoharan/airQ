import SwiftUI
import Charts
import RespiratoryKit

/// The main comparison always keeps symptoms immediately beside air and pollen.
struct TrendsPanels: View {
    let data: ChartData
    @Binding var selection: Date?
    let inspectDay: () -> Void
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        heading
                        Spacer(minLength: 8)
                        inspectButton
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        heading
                        inspectButton
                    }
                }
                if data.checkIns.contains(where: { $0.severity != nil }) || !data.hourly.isEmpty
                    || !data.waqi.isEmpty || !data.pollen.isEmpty {
                    Text("Tap a chart to select its day.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
        }
        .airQCard()
    }

    private var heading: some View {
        Text("Symptoms & surroundings").font(.headline).accessibilityAddTraits(.isHeader)
    }

    private var inspectButton: some View {
        Button("Inspect a day", systemImage: "calendar", action: inspectDay)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Opens details with a date picker and day navigation.")
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
    var alignsYAxis = false
    var yTicks: [Int]?
    @ChartContentBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var axisWidth = 32

    private var axisDates: [Date] {
        guard let last = data.days.indices.last else { return [] }
        return Array(Set([0, last / 3, last * 2 / 3, last])).sorted()
            .map { data.days[$0].interval.start }
    }

    private var chartSelection: Binding<Date?> {
        Binding(get: { selection }, set: { date in
            // Keep the selected day when Charts clears its gesture selection.
            guard let date, let day = data.day(at: date), day.interval.start != selection else { return }
            selection = day.interval.start
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Chart {
                if let selection, let day = data.day(at: selection) {
                    RectangleMark(xStart: .value("Selected day start", day.interval.start),
                                  xEnd: .value("Selected day end", day.interval.end))
                        .foregroundStyle(AirQStyle.accent.opacity(0.16))
                        .accessibilityHidden(true)
                }
                content()
            }
            .chartXScale(domain: data.domain.start...data.domain.end, range: .plotDimension(padding: 0))
            .chartXSelection(value: chartSelection)
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
                if showsYAxis {
                    if let yTicks {
                        AxisMarks(position: .leading, values: yTicks) { mark in
                            numericAxisContent(mark)
                        }
                    } else if alignsYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { mark in
                            numericAxisContent(mark)
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 3))
                    }
                }
            }
            .frame(height: typeSize.isAccessibilitySize ? height * 1.6 : height)
            if typeSize.isAccessibilitySize {
                Text("\(data.domain.start.formatted(.dateTime.month(.abbreviated).day())) – \(data.domain.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @AxisMarkBuilder private func numericAxisContent(_ mark: AxisValue) -> some AxisMark {
        AxisGridLine()
        AxisValueLabel {
            if let number = mark.as(Double.self) ?? mark.as(Int.self).map(Double.init) {
                Text(number, format: .number.precision(.fractionLength(0...1)))
                    .font(.caption2)
                    .frame(width: axisWidth, alignment: .leading)
            }
        }
    }
}
