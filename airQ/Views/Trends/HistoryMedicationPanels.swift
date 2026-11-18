import SwiftUI
import Charts
import RespiratoryKit

struct HistoryMedicationPanels: View {
    let data: ChartData
    @Binding var selection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if data.checkIns.contains(where: { $0.controllerAdherence != nil }) {
                TrendsPanel(title: "Controller medication taken", data: data, selection: $selection, height: 65,
                            showsYAxis: false) {
                    ForEach(data.checkIns, id: \.day) { point in
                        if let raw = point.controllerAdherence,
                           let answer = CheckInQuestionSet.ControllerAdherence(rawValue: raw) {
                            BarMark(x: .value("Day", point.day, unit: .day), y: .value("Answered", 1))
                                .foregroundStyle(by: .value("Answer", CheckInLabels.adherence(answer)))
                                .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("Controller medication: \(CheckInLabels.adherence(answer))")
                        }
                    }
                }
                .chartForegroundStyleScale(domain: CheckInQuestionSet.ControllerAdherence.allCases.map(CheckInLabels.adherence),
                                           range: [Color.green, .yellow, .red, .gray])
            }
            if data.checkIns.contains(where: { $0.rescueInhalerUses != nil }) {
                TrendsPanel(title: "Rescue inhaler uses", data: data, selection: $selection, height: 100) {
                    ForEach(data.checkIns, id: \.day) { point in
                        if let uses = point.rescueInhalerUses {
                            PointMark(x: .value("Day", point.day, unit: .day), y: .value("Uses", uses))
                                .foregroundStyle(AirQStyle.accent)
                                .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(uses) rescue inhaler uses")
                        }
                    }
                }
            }
            if data.checkIns.contains(where: { $0.peakFlowLPM != nil }) {
                TrendsPanel(title: "Peak flow (L/min)", data: data, selection: $selection, height: 100) {
                    ForEach(data.checkIns, id: \.day) { point in
                        if let value = point.peakFlowLPM {
                            PointMark(x: .value("Day", point.day, unit: .day), y: .value("L/min", value))
                                .foregroundStyle(.indigo)
                                .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("Peak flow \(value) litres per minute")
                        }
                    }
                }
            }
            Text("These are the answers you saved. Gaps mean no answer was recorded.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
