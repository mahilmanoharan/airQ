import SwiftUI
import RespiratoryKit

/// A descriptive workspace: symptoms and environmental readings share a time axis.
struct TrendsView: View {
    @State private var model: ChartViewModel
    @State private var selection: Date?
    @Environment(\.historyPeriod) private var period
    @Environment(\.setHistoryPeriod) private var setPeriod
    @Environment(\.recordRevision) private var revision
    @Environment(\.selectedTab) private var tab
    @Environment(\.openRoute) private var openRoute
    @State private var loadedKey: HistoryLoadKey?
    @State private var retry = 0

    private var loadKey: HistoryLoadKey {
        HistoryLoadKey(period: period, revision: revision, isActive: tab == .trends, retry: retry)
    }

    init(records: RecordStore, detections: DetectionStore?) {
        _model = State(initialValue: ChartViewModel(records: records, detections: detections,
                                                    tuning: { TuningSettings.load() }))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Symptoms beside air quality and pollen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("History period", selection: Binding(get: { period }, set: { setPeriod($0) })) {
                        ForEach(HistoryPeriod.allCases) { span in Text(span.title).tag(span) }
                    }
                    .pickerStyle(.segmented)
                    if model.isLoading || loadedKey != loadKey {
                        ProgressView("Loading your history…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if let message = model.errorMessage {
                        ContentUnavailableView {
                            Label("History couldn't load", systemImage: "exclamationmark.triangle")
                        } description: { Text(message) } actions: {
                            Button("Try again") { retry += 1 }.buttonStyle(.bordered)
                        }
                    } else if let data = model.data {
                        HistoryCoverageCard(data: data)
                        if data.hasHistoryContent {
                            TrendsPanels(data: data, selection: $selection).id("comparison")
                            if let table = model.symptomDays, !table.isEmpty {
                                SymptomDaysCard(table: table).id("symptomDays")
                            }
                            HistoryDetails(data: data, selection: $selection)
                            Button("Prepare a report", systemImage: "doc.text") { openRoute(.report) }
                                .buttonStyle(.bordered).controlSize(.large)
                                .frame(maxWidth: .infinity)
                            DisclosureGroup("About these readings") { TrendsLegend().padding(.top, 8) }
                                .airQCard()
                        } else {
                            HistoryEmptyState()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            #if DEBUG
            .task(id: model.data != nil) {
                guard model.data != nil, let anchor = UserDefaults.standard.string(forKey: "trendsScrollTo") else { return }
                await Task.yield()
                proxy.scrollTo(anchor == "hourOfDay" ? "listening" : anchor, anchor: .top)
            }
            #endif
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let data = model.data, loadedKey == loadKey, selection != nil, !model.isLoading, model.errorMessage == nil {
                TrendsSelectionSummary(data: data, selection: $selection)
                    .padding(.horizontal).padding(.vertical, 8)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
        .task(id: loadKey) {
            guard loadKey.isActive else { return }
            let requested = loadKey
            loadedKey = nil
            selection = nil
            model.span = requested.period
            await model.load()
            guard !Task.isCancelled, requested == loadKey else { return }
            loadedKey = requested
        }
        .refreshable { retry += 1 }
        .tint(AirQStyle.accent)
    }
}
