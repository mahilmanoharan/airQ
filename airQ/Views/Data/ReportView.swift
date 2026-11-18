import SwiftUI
import RespiratoryKit

/// The same read-time summary included in the archive, presented for an appointment.
struct ReportView: View {
    @Environment(\.historyPeriod) private var period
    @Environment(\.setHistoryPeriod) private var setPeriod
    @Environment(\.recordRevision) private var revision
    @Environment(\.selectedTab) private var tab
    @Environment(\.recordStore) private var records
    @Environment(\.detectionStore) private var detections
    @State private var model: ClinicianSummaryViewModel?
    @State private var loadedKey: HistoryLoadKey?
    @State private var reload = 0

    private var loadKey: HistoryLoadKey {
        HistoryLoadKey(period: period, revision: revision, isActive: tab == .report, retry: reload)
    }

    private var currentSummary: ClinicianSummary? {
        guard loadedKey == loadKey,
              model?.isLoading == false, model?.errorMessage == nil else { return nil }
        return model?.summary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AirQPageHeader(eyebrow: "REPORT", title: "Your breathing record",
                               detail: "A summary to read together at your next appointment.")
                Picker("Report period", selection: Binding(get: { period }, set: { setPeriod($0) })) {
                    ForEach(HistoryPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reportPeriod")

                if let summary = currentSummary {
                    ReportOverview(summary: summary, periodTitle: period.title)
                    ShareLink(item: summary.text, subject: Text("airQ summary: \(summary.firstDayKey) to \(summary.lastDayKey)")) {
                        Label("Share summary", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                .foregroundStyle(AirQStyle.onAccent)
                    .controlSize(.large)
                    .tint(AirQStyle.accent)
                    .accessibilityIdentifier("shareReportSummary")
                    SummarySection(summary: summary)
                } else if let message = model?.errorMessage, model?.isLoading == false, loadedKey == loadKey {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Report couldn't be loaded", systemImage: "exclamationmark.circle")
                            .font(.headline)
                        Text(message)
                        Button("Try again") { reload += 1 }
                            .buttonStyle(.bordered)
                    }
                    .airQCard()
                } else if records == nil {
                    ContentUnavailableView("Report unavailable", systemImage: "doc.text",
                                           description: Text("Your saved record couldn't be opened."))
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing \(period.title.lowercased()) summary…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .airQCard()
                }
                ReportAdvancedExport()
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadKey) { if loadKey.isActive { await loadSummary() } }
        .refreshable { reload += 1 }
    }

    private func loadSummary() async {
        guard let records else { return }
        let requested = loadKey
        loadedKey = nil
        if model == nil {
            model = ClinicianSummaryViewModel(records: records, detections: detections,
                                             tuning: { TuningSettings.load() })
        }
        await model?.load(period: requested.period.exportPeriod)
        guard !Task.isCancelled, requested == loadKey else { return }
        loadedKey = requested
    }
}
