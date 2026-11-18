import SwiftUI
import SwiftData
import RespiratoryKit

/// Exports the record (all of it, or a recent period) as CSV for analysis. The export is a copy; nothing is removed from
/// the device. Regular exports are the only backup besides an iCloud device backup.
enum ExportPreferences {
    /// When the last full export finished; erased with the record (`DataEraser`).
    static let lastExportAtKey = "lastExportAt"
}

struct ExportView: View {
    @State private var model: ExportViewModel
    @AppStorage(ExportPreferences.lastExportAtKey) private var lastExportAt: Double = 0
    @AppStorage("exportPeriod") private var period = ExportPeriod.everything
    @Environment(\.recordStore) private var records
    @Environment(\.detectionStore) private var detections

    init(container: ModelContainer) {
        _model = State(initialValue: ExportViewModel(container: container, appVersion: AppVersion.current,
                                                     didExportEverything: { UserDefaults.standard.set($0.timeIntervalSince1970, forKey: ExportPreferences.lastExportAtKey) }))
    }

    var body: some View {
        List {
            Section {
                ExportContentsRow(symbol: "waveform", title: "Listening sessions and every classifier window")
                ExportContentsRow(symbol: "checkmark.bubble", title: "Review verdicts and legacy detections")
                ExportContentsRow(symbol: "checklist", title: "Check-ins and context events")
                ExportContentsRow(symbol: "aqi.medium", title: "Air quality and pollen requests, with raw responses")
                ExportContentsRow(symbol: "book.closed", title: "A README, data dictionary and a manifest with checksums")
                ExportContentsRow(symbol: "text.document", title: "A readable summary of this period, as summary.txt")
            } header: {
                Text("Included")
            } footer: {
                Text("One CSV per table, joined by IDs, preserving the stored rows in the chosen period. Audio was never stored.")
            }
            Section {
                Picker("Period", selection: $period) {
                    ForEach(ExportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .disabled(model.isExporting)
                .onChange(of: period) { model.periodChanged() }
            } footer: {
                if period != .everything {
                    Text("Only rows recorded in this period are included, so the export is a partial copy and not a backup. Life events you saved earlier are not included.")
                }
            }
            Section {
                switch model.phase {
                case .idle:
                    Button("Create export", systemImage: "square.and.arrow.up", action: startExport)
                case .exporting:
                    HStack { ProgressView(); Text("Preparing export…").foregroundStyle(.secondary) }
                case .ready(let url, let manifest):
                    ShareLink(item: url) { Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
                    ExportSummary(manifest: manifest)
                    Button("Create again", action: startExport)
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Try again", action: startExport)
                }
            } footer: {
                if lastExportAt > 0 {
                    Text("Last full export \(Date(timeIntervalSince1970: lastExportAt).formatted(.relative(presentation: .named))).")
                }
            }
        }
        .navigationTitle("Raw export")
        // The archive holds the whole record unencrypted: don't leave it in the temporary folder after
        // the person has left the screen (a share sheet keeps this view on screen while it's open).
        .onDisappear { model.leave() }
        .task {
            if let records {
                let detections = detections
                model.summaryProvider = { period, requestedAt, range in
                    let summary = ClinicianSummaryViewModel(records: records, detections: detections,
                                                            tuning: { TuningSettings.load() }, now: { requestedAt })
                    await summary.load(period: period, recordedIn: range)
                    return summary.summary?.text
                }
            }
            #if DEBUG
            // Simulator verification without UI automation: `-autoExport YES`.
            if UserDefaults.standard.bool(forKey: "autoExport"), case .idle = model.phase,
               AppServices.shared.registerExport(model) {
                await model.run(period: period)
            }
            #endif
        }
    }

    private func startExport() {
        guard AppServices.shared.registerExport(model) else { return }
        model.start(period: period)
    }
}

private struct ExportContentsRow: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
    }
}

private struct ExportSummary: View {
    let manifest: ExportManifest

    var body: some View {
        DisclosureGroup("Files") {
            ForEach(manifest.files.filter { $0.rows != nil }, id: \.name) { file in
                LabeledContent(file.name, value: "\(file.rows ?? 0) rows")
                    .font(.caption)
            }
            LabeledContent("Raw responses", value: "\(manifest.files.count(where: { $0.name.hasPrefix("raw/") }))")
                .font(.caption)
        }
    }
}
