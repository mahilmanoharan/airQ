import SwiftUI
import RespiratoryKit

struct TrendsView: View {
    @State private var model: ChartViewModel
    @State private var selection: Date?
    @State private var detail: HistoryDetail?
    @State private var loadedKey: HistoryLoadKey?
    @State private var retry = 0
    @Environment(\.historyPeriod) private var period
    @Environment(\.recordRevision) private var revision
    @Environment(\.selectedTab) private var tab
    @Environment(\.tabOpenRevision) private var tabOpenRevision
    @Environment(\.openRoute) private var openRoute

    private var loadKey: HistoryLoadKey {
        HistoryLoadKey(period: period, revision: revision, isActive: tab == .trends, retry: retry)
    }

    private var isLoading: Bool { model.isLoading || loadedKey != loadKey }

    init(records: RecordStore, detections: DetectionStore?) {
        _model = State(initialValue: ChartViewModel(records: records, detections: detections,
                                                    tuning: { TuningSettings.load() }))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HistoryPeriodPicker(title: "History period")
                    .accessibilityIdentifier("historyPeriod")

                historyContent { data in
                    HistoryJournal(data: data) { open($0, data: data) }
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AirQStyle.atmosphere }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { destination in
            NavigationStack {
                historyContent { data in
                    HistoryDetailPage(detail: destination, data: data, symptomDays: model.symptomDays,
                                      selection: $selection)
                }
                .navigationTitle(destination.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } }
                }
            }
            .environment(\.openRoute) { route in
                detail = nil
                openRoute(route)
            }
        }
        .onChange(of: period) { selection = nil }
        .onChange(of: tabOpenRevision) { detail = nil }
        .task(id: loadKey) {
            let requested = loadKey
            guard requested.isActive else {
                detail = nil
                selection = nil
                return
            }
            model.span = requested.period
            await model.load()
            guard !Task.isCancelled, requested == loadKey else { return }
            if model.errorMessage == nil, let data = model.data {
                if let selection, data.day(at: selection) == nil { self.selection = data.days.last?.interval.start }
                #if DEBUG
                if loadedKey == nil, let anchor = UserDefaults.standard.string(forKey: "trendsScrollTo") {
                    if anchor == "hourOfDay" {
                        if data.hasListeningHistory { open(.listening, data: data) }
                    } else if data.hasHistoryContent {
                        open(.comparison, data: data)
                    }
                }
                #endif
            }
            loadedKey = requested
        }
        .refreshable { retry += 1 }
        .tint(AirQStyle.accent)
    }

    @ViewBuilder private func historyContent<Content: View>(@ViewBuilder _ content: (ChartData) -> Content) -> some View {
        if isLoading {
            ProgressView("Loading your history…")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if let message = model.errorMessage {
            ContentUnavailableView {
                Label("History couldn't load", systemImage: "exclamationmark.triangle")
            } description: { Text(message) } actions: {
                Button("Try again") { retry += 1 }.buttonStyle(.bordered)
            }
        } else if let data = model.data {
            content(data)
        }
    }

    private func open(_ destination: HistoryDetail, data: ChartData) {
        if destination == .day && selection == nil { selection = data.days.last?.interval.start }
        detail = destination
    }
}
