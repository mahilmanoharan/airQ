import SwiftUI
import RespiratoryKit

enum HistoryDetail: Hashable, Identifiable {
    case day, comparison, listening

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day details"
        case .comparison: "Compare with air & pollen"
        case .listening: "Listening history"
        }
    }
}

struct HistoryDetailPage: View {
    let detail: HistoryDetail
    let data: ChartData
    let symptomDays: SymptomDaysByLevel?
    @Binding var selection: Date?
    @State private var showingDayDetails = false
    @Environment(\.openRoute) private var openRoute
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if detail == .day {
            dayDetails
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if detail == .comparison {
                            comparison
                        } else {
                            HistoryListeningDetails(data: data, selection: $selection)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                #if DEBUG
                .task {
                    if let anchor = UserDefaults.standard.string(forKey: "trendsScrollTo") {
                        await Task.yield()
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
                #endif
            }
            .background {
                if detail == .comparison { AirQStyle.background } else { AirQStyle.page }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { selectedDayInset }
            .navigationDestination(isPresented: $showingDayDetails) {
                dayDetails.navigationTitle(HistoryDetail.day.title)
            }
        }
    }

    private var dayDetails: some View {
        TrendsSelectionSummary(data: data, selection: $selection, presentation: .day)
    }

    private var comparison: some View {
        Group {
            HistoryCoverage(data: data)
            TrendsPanels(data: data, selection: comparisonSelection)
            .id("comparison")
            if let symptomDays, !symptomDays.isEmpty {
                SymptomDaysCard(table: symptomDays).id("symptomDays")
            }
            HistoryDetails(data: data, selection: $selection)
            Button("Prepare a report", systemImage: "doc.text") { openRoute(.report) }
                .buttonStyle(.bordered).controlSize(.large)
                .frame(maxWidth: .infinity)
            DisclosureGroup("About these readings") { TrendsLegend().padding(.top, 8) }
                .airQCard()
        }
    }

    private var comparisonSelection: Binding<Date?> {
        Binding(get: { selection ?? data.days.last?.interval.start }, set: { selection = $0 })
    }

    @ViewBuilder private var selectedDayInset: some View {
        if detail == .comparison {
            HistoryComparisonDock(data: data, selection: comparisonSelection) { showingDayDetails = true }
        } else if let selection, let day = data.day(at: selection) {
            Group {
                if typeSize.isAccessibilitySize {
                    Button { showingDayDetails = true } label: {
                        Label("Day details, \(DayKeys.display(day.dayKey, style: .dateTime.month(.abbreviated).day()))",
                              systemImage: "calendar")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    TrendsSelectionSummary(data: data, selection: $selection, presentation: .chart {
                        self.selection = nil
                    })
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
    }
}
