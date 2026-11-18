import SwiftUI
import CoreTransferable
import RespiratoryKit
import UniformTypeIdentifiers

struct ReportView: View {
    @Environment(\.historyPeriod) private var period
    @Environment(\.setHistoryPeriod) private var setPeriod
    @Environment(\.recordRevision) private var revision
    @Environment(\.selectedTab) private var tab
    @Environment(\.recordStore) private var records
    @Environment(\.detectionStore) private var detections
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: ClinicianSummaryViewModel?
    @State private var loadedKey: HistoryLoadKey?
    @State private var pdf: ReportPDF?
    @State private var pdfError: String?
    @State private var reload = 0
    @State private var showsPreview = false

    private var loadKey: HistoryLoadKey {
        HistoryLoadKey(period: period, revision: revision, isActive: tab == .report, retry: reload)
    }

    private var currentReport: ClinicianReport? {
        guard loadedKey == loadKey,
              model?.isLoading == false, model?.errorMessage == nil else { return nil }
        return model?.report
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appointmentReport
                ReportAdvancedExport()
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(AirQStyle.page)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPreview) {
            ReportPreview(isPresented: $showsPreview) {
                if let report = currentReport {
                    ReportOverview(summary: report.summary)
                    ReportCoverage(summary: report.summary)
                    ReportTimeline(report: report)
                    SummarySection(summary: report.summary)
                } else {
                    reportStatus.airQCard()
                }
            }
        }
        .onChange(of: tab) { _, selected in
            if selected != .report { showsPreview = false }
        }
        .task(id: loadKey) { [requested = loadKey] in await loadReport(for: requested) }
        .refreshable { reload += 1 }
    }

    private var appointmentReport: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prepare for an appointment")
                .font(.title2.weight(.semibold)).fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            periodPicker
            if let report = currentReport {
                ReportIntroduction(summary: report.summary)
                VStack(spacing: 10) {
                    Button {
                        showsPreview = true
                    } label: {
                        Label("Preview report", systemImage: "doc.text")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("previewReport")
                    shareReport
                }
            } else {
                reportStatus
            }
        }
        .airQCard()
    }

    private var periodPicker: some View {
        let picker = Picker("Report period", selection: Binding(get: { period }, set: { setPeriod($0) })) {
            ForEach(HistoryPeriod.allCases) { Text($0.title).tag($0) }
        }
        return Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
        }
        .accessibilityIdentifier("reportPeriod")
    }

    @ViewBuilder private var reportStatus: some View {
        if let message = model?.errorMessage, model?.isLoading == false, loadedKey == loadKey {
            VStack(alignment: .leading, spacing: 8) {
                Label("Report couldn't be loaded", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text(message)
                Button("Try again") { reload += 1 }
                    .buttonStyle(.bordered)
            }
        } else if records == nil {
            Text("Your saved record couldn't be opened.")
        } else {
            ProgressView("Preparing your report…")
        }
    }

    @ViewBuilder private var shareReport: some View {
        if let pdf {
            ShareLink(item: pdf, subject: Text("airQ Respiratory Report"),
                      preview: SharePreview("airQ Respiratory Report")) {
                Label("Share PDF", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AirQStyle.onAccent)
            .controlSize(.large)
            .tint(AirQStyle.accent)
            .accessibilityIdentifier("shareReportSummary")
        } else if let pdfError {
            VStack(alignment: .leading, spacing: 8) {
                Text(pdfError)
                Button("Try again") { reload += 1 }.buttonStyle(.bordered)
            }
        }
    }

    private func loadReport(for requested: HistoryLoadKey) async {
        guard requested == loadKey, !Task.isCancelled else { return }
        loadedKey = nil
        pdf = nil
        pdfError = nil
        guard requested.isActive, let records else {
            model = nil
            return
        }
        let loader = model ?? ClinicianSummaryViewModel(records: records, detections: detections,
                                                        tuning: { TuningSettings.load() })
        model = loader
        await loader.loadReport(period: requested.period)
        guard !Task.isCancelled, requested == loadKey else { return }
        if let report = loader.report {
            do {
                let data = try await report.pdfData()
                guard !Task.isCancelled, requested == loadKey else { return }
                pdf = ReportPDF(data: data, fileName: "airQ-\(report.summary.firstDayKey)-to-\(report.summary.lastDayKey).pdf")
            } catch {
                guard !Task.isCancelled, requested == loadKey else { return }
                pdfError = error.localizedDescription
            }
        }
        loadedKey = requested
    }
}

private nonisolated struct ReportPDF: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}
