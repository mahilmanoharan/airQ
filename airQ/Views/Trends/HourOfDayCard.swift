import SwiftUI
import Charts
import RespiratoryKit

/// When in the day detections happened, and how long airQ was listening in each hour. Counts alone
/// would mislead (a night's listening versus a day's), so the listening time is drawn beneath them
/// on the same hours. Descriptive only: no rate, score or trend.
struct HourOfDayCard: View {
    let data: ChartData
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hours: [ChartData.HourBin] { data.hourOfDay }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By hour of day").font(.headline)
            Text("Detected \(data.detectionLabel) events by local hour, and minutes of listening in each hour.")
                .font(.caption)
                .foregroundStyle(.secondary)
            panel(title: "Events", accessibilityUnit: "events", color: .orange) { bin in Double(bin.count) }
            panel(title: "Listening (minutes)", accessibilityUnit: "minutes listened", color: .blue) { bin in
                bin.listeningSeconds / 60
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func panel(title: String, accessibilityUnit: String, color: Color,
                       value: @escaping (ChartData.HourBin) -> Double) -> some View {
        let peak = hours.map(value).max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                // The y-axis is hidden so both panels share one plot width and their hours line up.
                Text("most in one hour: \(peak.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Chart(hours) { bin in
                BarMark(x: .value("Hour", bin.hour), y: .value(title, value(bin)))
                    .foregroundStyle(color)
                    .accessibilityLabel(Self.hourLabel(bin.hour))
                    .accessibilityValue("\(value(bin).formatted(.number.precision(.fractionLength(0...1)))) \(accessibilityUnit)")
            }
            .chartXScale(domain: -0.5...23.5)
            .chartYScale(domain: 0...max(peak, 1))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: typeSize.isAccessibilitySize ? [0, 12] : [0, 6, 12, 18]) { mark in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = mark.as(Int.self) { Text(Self.axisLabel(hour)) }
                    }
                }
            }
            .frame(height: typeSize.isAccessibilitySize ? 160 : 90)
        }
    }

    /// "12 AM", "6 AM", ... in the user's own 12/24-hour style.
    static func axisLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date(timeIntervalSince1970: 0)) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    static func hourLabel(_ hour: Int) -> String { "Hour starting \(axisLabel(hour))" }
}
