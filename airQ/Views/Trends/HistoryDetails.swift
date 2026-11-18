import SwiftUI
import Charts
import RespiratoryKit

struct HistoryDetails: View {
    let data: ChartData
    @Binding var selection: Date?
    @State private var listeningExpanded = false

    var body: some View {
        if data.hasHourOfDayData {
            DisclosureGroup("Sounds & listening", isExpanded: $listeningExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sound counts cover only the time airQ was listening and depend on your sensitivity setting.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HistoryListeningPanels(data: data, selection: $selection)
                    HourOfDayCard(data: data).id("hourOfDay")
                }
                .padding(.top, 12)
            }
            .airQCard()
            .id("listening")
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.string(forKey: "trendsScrollTo") == "hourOfDay" { listeningExpanded = true }
            }
            #endif
        }
        if data.hasMedicationAnswers {
            DisclosureGroup("Medication & peak flow") {
                HistoryMedicationPanels(data: data, selection: $selection).padding(.top, 12)
            }
            .airQCard()
        }
        if !data.context.isEmpty {
            DisclosureGroup("Life events") {
                VStack(alignment: .leading, spacing: 16) {
                    TrendsPanel(title: "Events you recorded", data: data, selection: $selection,
                                height: CGFloat(40 + 24 * Set(data.context.map(\.category)).count)) {
                        ForEach(data.context) { span in
                            RectangleMark(xStart: .value("Start", span.start), xEnd: .value("End", span.end),
                                          y: .value("Event", ContextEventLabels.title(span.category)), height: 14)
                                .foregroundStyle(.indigo.opacity(span.isOngoing ? 0.45 : 0.75))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel(ContextEventLabels.title(span.category))
                                .accessibilityValue(TrendsLabels.contextValue(span))
                        }
                    }
                    ForEach(data.context) { span in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ContextEventLabels.title(span.category)).font(.subheadline.weight(.semibold))
                            Text(TrendsLabels.contextValue(span)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 12)
            }
            .airQCard()
        }
    }
}

struct HistoryListeningPanels: View {
    let data: ChartData
    @Binding var selection: Date?

    var body: some View {
        TrendsPanel(title: "\(SoundLabels.display(data.detectionLabel)) sounds heard", data: data,
                    selection: $selection, height: 110) {
            ForEach(data.detections, id: \.day) { bar in
                BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Events", bar.count))
                    .foregroundStyle(.purple)
                    .accessibilityLabel(bar.day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(bar.count) events")
            }
        }
        TrendsPanel(title: "Listening time (minutes)", data: data, selection: $selection, height: 90) {
            ForEach(data.detections, id: \.day) { bar in
                BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Minutes", bar.listeningSeconds / 60))
                    .foregroundStyle(.blue)
                    .accessibilityLabel(bar.day.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(Int(bar.listeningSeconds / 60)) minutes listening")
            }
        }
    }
}
