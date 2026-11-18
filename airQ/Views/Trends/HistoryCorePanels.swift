import SwiftUI
import Charts
import RespiratoryKit

struct HistorySymptomsPanel: View {
    let data: ChartData
    @Binding var selection: Date?

    var body: some View {
        TrendsPanel(title: "Daytime symptoms", data: data, selection: $selection, height: 95, yTicks: [0, 1, 2, 3]) {
            ForEach(data.checkIns, id: \.day) { point in
                if let severity = point.severity {
                    PointMark(x: .value("Day", point.day, unit: .day), y: .value("Severity", severity))
                        .symbolSize(45)
                        .foregroundStyle(AirQStyle.accent)
                        .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(severity == 0 ? "No daytime symptoms" : "Severity \(severity) of 3")
                }
            }
        }
        .chartYScale(domain: -0.2...3.2)
        Text("0 none · 1 mild · 2 moderate · 3 severe")
            .font(.caption).foregroundStyle(.secondary)
        if data.checkIns.contains(where: { $0.daytimeSymptoms == true && $0.severity == nil }) {
            Text("Some days report symptoms without a severity; inspect the day for details.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HistoryAirPanel: View {
    let data: ChartData
    @Binding var selection: Date?

    var body: some View {
        TrendsPanel(title: "Air quality (AQI)", data: data, selection: $selection, height: 110, alignsYAxis: true) {
            ForEach(Array(data.hourly.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Time", point.date), y: .value("AQI", point.value))
                    .symbolSize(8)
                    .foregroundStyle(by: .value("Source", "Hourly · Google"))
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue("Hourly AQI \(point.value)")
            }
            ForEach(Array(data.waqi.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Time", point.date), y: .value("AQI", point.value))
                    .symbol(.diamond).symbolSize(30)
                    .foregroundStyle(by: .value("Source", "Station · WAQI"))
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue("Station AQI \(point.value)")
            }
        }
        .chartForegroundStyleScale(domain: ["Hourly · Google", "Station · WAQI"], range: [Color.blue, Color.orange])
    }
}

struct HistoryPollenPanel: View {
    let data: ChartData
    @Binding var selection: Date?

    var body: some View {
        TrendsPanel(title: "Pollen forecast (0–5)", data: data, selection: $selection, height: 110, yTicks: [0, 1, 3, 5]) {
            ForEach(Array(data.pollen.enumerated()), id: \.offset) { _, bar in
                BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Pollen", bar.upi))
                    .foregroundStyle(by: .value("Type", TrendsLabels.pollen(bar.code)))
                    .position(by: .value("Type", TrendsLabels.pollen(bar.code)))
                    .accessibilityLabel(bar.day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(TrendsLabels.pollen(bar.code)) pollen index \(bar.upi)")
                if bar.upi == 0 {
                    PointMark(x: .value("Day", bar.day, unit: .day), y: .value("Pollen", 0))
                        .foregroundStyle(by: .value("Type", TrendsLabels.pollen(bar.code)))
                        .position(by: .value("Type", TrendsLabels.pollen(bar.code)))
                        .symbolSize(20)
                        .accessibilityHidden(true)
                }
            }
        }
        .chartYScale(domain: 0...5)
        .chartForegroundStyleScale(domain: ["Grass", "Tree", "Weed"], range: [Color.teal, .indigo, .orange])
    }
}
