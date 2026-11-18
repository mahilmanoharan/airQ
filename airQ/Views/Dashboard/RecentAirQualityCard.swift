import SwiftUI
import Charts
import Accessibility
import AirQualityKit
import RespiratoryKit

/// The last 48 hours of stored AQI: Google's hourly history (US EPA index) as a line and this
/// device's WAQI station readings as dots. Drawn from the record store only, so it makes no requests.
struct RecentAirQualityCard: View {
    @State private var model: RecentAirQualityViewModel
    /// Changes whenever an environmental attempt is saved (a new station reading or history page),
    /// so the card reloads after the write rather than racing it.
    let refreshKey: Int

    init(records: RecordStore, place: RecordPlace?, refreshKey: Int) {
        _model = State(initialValue: RecentAirQualityViewModel(records: records, place: place))
        self.refreshKey = refreshKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 48 hours").font(.headline)
                Spacer()
                if let range = model.valueRange {
                    Text("AQI \(range.lowerBound)–\(range.upperBound)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let message = model.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            } else if model.hasLoaded && model.isEmpty {
                Text("Hourly history appears after airQ has collected it (at most once a day).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.hasLoaded {
                RecentAirQualityChart(model: model)
                Text("Hourly values are Google's US EPA index; dots are station readings from when airQ was opened.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 140)
            }
        }
        .dashboardCard()
        .task(id: refreshKey) { await model.load() }
    }
}

private struct RecentAirQualityChart: View {
    let model: RecentAirQualityViewModel
    @State private var selection: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let hourlySeries = "Hourly (Google)"
    private static let stationSeries = "Station (WAQI)"

    var body: some View {
        Chart {
            // AQI category bands behind the data, clipped to the visible range.
            ForEach(AirQualityPresentation.bands.filter { $0.range.lowerBound < yUpperBound }, id: \.category) { band in
                RectangleMark(xStart: .value("Start", model.window.start), xEnd: .value("End", model.window.end),
                              yStart: .value("Band low", max(band.range.lowerBound - 1, 0)),
                              yEnd: .value("Band high", min(band.range.upperBound, yUpperBound)))
                    .foregroundStyle(band.color.opacity(0.07))
                    .accessibilityHidden(true)
            }
            // One series per run of consecutive hours: the line breaks at a missing hour.
            ForEach(Array(model.hourlyRuns.enumerated()), id: \.offset) { run, points in
                HourlyRunMarks(run: run, points: points, source: Self.hourlySeries)
            }
            ForEach(Array(model.station.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Time", point.date), y: .value("AQI", point.value))
                    .symbolSize(40)
                    .foregroundStyle(by: .value("Source", Self.stationSeries))
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue("Station AQI \(point.value), \(AirQualityPresentation.category(for: point.value))")
            }
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(date: selection, values: model.values(near: selection))
                    }
            }
        }
        .chartXSelection(value: $selection)
        .accessibilityChartDescriptor(RecentAirQualityAudioGraph(hourly: model.hourly, station: model.station,
                                                                  window: model.window))
        .chartForegroundStyleScale([Self.hourlySeries: Color.blue, Self.stationSeries: Color.orange])
        .chartXScale(domain: model.window.start...model.window.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: typeSize.isAccessibilitySize ? 24 : 12)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
            }
        }
        .chartYScale(domain: 0...yUpperBound)
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: typeSize.isAccessibilitySize ? 280 : 160)
    }

    /// At least the "Moderate" band's top, so a clean day doesn't look alarming by filling the plot.
    private var yUpperBound: Int {
        max(100, ((model.valueRange?.upperBound ?? 0) / 50 + 1) * 50)
    }
}

private struct SelectionCallout: View {
    let date: Date
    let values: (hourly: EnvironmentSeries.AQIPoint?, station: EnvironmentSeries.AQIPoint?)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .font(.caption2.weight(.semibold))
            if let hourly = values.hourly {
                Text("Hourly \(hourly.value) · \(AirQualityPresentation.category(for: hourly.value))")
            }
            if let station = values.station {
                Text("Station \(station.value) at \(station.date.formatted(date: .omitted, time: .shortened))")
            }
            if values.hourly == nil && values.station == nil {
                Text("No stored value")
            }
        }
        .font(.caption2)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background).shadow(radius: 1))
    }
}

/// VoiceOver Audio Graph for the 48-hour chart: the hourly line as a continuous series and the
/// station readings as discrete points, on the chart's own time window.
private struct RecentAirQualityAudioGraph: AXChartDescriptorRepresentable {
    let hourly: [EnvironmentSeries.AQIPoint]
    let station: [EnvironmentSeries.AQIPoint]
    let window: DateInterval

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: window.start.timeIntervalSince1970...window.end.timeIntervalSince1970,
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) }
        let highest = (hourly + station).map(\.value).max() ?? 0
        let yAxis = AXNumericDataAxisDescriptor(title: "AQI", range: 0...Double(max(100, highest)),
                                                gridlinePositions: [50, 100, 150]) { "AQI \(Int($0))" }
        func points(_ values: [EnvironmentSeries.AQIPoint]) -> [AXDataPoint] {
            values.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: Double($0.value)) }
        }
        return AXChartDescriptor(
            title: "Air quality, last 48 hours",
            summary: "Hourly values are Google's US EPA index; station readings are from when airQ was opened.",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
            series: [
                AXDataSeriesDescriptor(name: "Hourly (Google)", isContinuous: true, dataPoints: points(hourly)),
                AXDataSeriesDescriptor(name: "Station (WAQI)", isContinuous: false, dataPoints: points(station)),
            ])
    }
}

/// One contiguous run of hourly values: a line, or a dot when the run is a single hour.
private struct HourlyRunMarks: ChartContent {
    let run: Int
    let points: [EnvironmentSeries.AQIPoint]
    let source: String

    var body: some ChartContent {
        ForEach(points, id: \.date) { point in
            LineMark(x: .value("Time", point.date), y: .value("AQI", point.value), series: .value("Run", "hourly-\(run)"))
                .interpolationMethod(.monotone)
                .foregroundStyle(by: .value("Source", source))
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                .accessibilityValue(Self.spoken(point.value))
        }
        if points.count == 1, let point = points.first {
            PointMark(x: .value("Time", point.date), y: .value("AQI", point.value))
                .symbolSize(12)
                .foregroundStyle(by: .value("Source", source))
        }
    }

    private static func spoken(_ value: Int) -> String {
        "Hourly AQI \(value), \(AirQualityPresentation.category(for: value))"
    }
}
