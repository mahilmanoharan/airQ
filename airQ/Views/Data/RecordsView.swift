import SwiftUI
import AirQualityKit
import RespiratoryKit
import SwiftData

/// What airQ has saved, in plain terms, with the diagnostics behind an "Advanced details" disclosure.
/// Read-only: everything is derived at read time and nothing here writes.
struct RecordsView: View {
    @State private var model: RecordsViewModel
    @State private var storageBytes: Int64?
    @State private var showsAdvanced = false
    @Environment(\.respiratoryContainer) private var container

    init(store: any RecordReading) {
        let limits = Dictionary(uniqueKeysWithValues: RollingRequestBudget.freeTierSafeLimits.map { ($0.key.rawValue, $0.value) })
        _model = State(initialValue: RecordsViewModel(
            store: store, usageLimits: limits, usageWindow: RollingRequestBudget.window,
            historyProviders: [EnvironmentalProvider.googleAirQuality.rawValue]))
    }

    var body: some View {
        List {
            if let message = model.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
            if let counts = model.counts {
                RecordsSummarySection(counts: counts, storageBytes: storageBytes)
            }
            RecordsDaysSection(days: model.days, collected: model.collectedDayCount, missing: model.missingDayCount)
            // The technical detail (provider usage, history coverage, raw counts, request log) is for
            // troubleshooting and for people reading the record with a clinician or statistician.
            Section {
                DisclosureGroup("Advanced details", isExpanded: $showsAdvanced) {
                    RecordsAdvancedDetails(model: model)
                }
            } footer: {
                Text("Where the numbers come from, how much of Google's free allowance is used, and every request airQ made.")
            }
        }
        .navigationTitle("Stored data")
        .overlay { if model.isLoading && !model.hasLoaded { ProgressView() } }
        .task {
            async let size: Int64? = Task.detached { [url = container?.configurations.first?.url] in
                url.flatMap(RespiratoryStore.diskUsage(ofStoreAt:))
            }.value
            await model.load()
            storageBytes = await size
        }
        .refreshable { await model.load() }
    }
}

/// What a person wants to know: what has been saved, in their own terms.
private struct RecordsSummarySection: View {
    let counts: RecordCounts
    let storageBytes: Int64?

    var body: some View {
        Section {
            LabeledContent("Check-ins", value: "\(counts.checkIns)")
            LabeledContent("Life events", value: "\(counts.contextEvents)")
            LabeledContent("Listening sessions", value: "\(counts.listeningSessions)")
            if let storageBytes {
                LabeledContent("Space used on this iPhone", value: storageBytes.formatted(.byteCount(style: .file)))
            }
        } header: {
            Text("What airQ has saved")
        } footer: {
            Text("Everything stays on this iPhone and is included in device backups. Export makes a copy you can keep or share; Erase all data removes it.")
        }
    }
}

/// Provider usage, history coverage, raw row counts and the request log.
private struct RecordsAdvancedDetails: View {
    let model: RecordsViewModel

    var body: some View {
        Group {
            ForEach(model.usage) { usage in
                LabeledContent("\(RecordLabels.provider(usage.provider)) requests (31 days)") {
                    Text("\(usage.used) of \(usage.limit)")
                        .foregroundStyle(usage.used >= usage.limit ? .red : .secondary)
                }
            }
            ForEach(model.coverage.sorted(by: { $0.key < $1.key }), id: \.key) { provider, coverage in
                RecordsCoverageRow(provider: provider, coverage: coverage)
            }
            if let counts = model.counts {
                RecordsCountsRows(counts: counts)
            }
            Text("Recent requests").font(.subheadline.weight(.semibold))
            if model.attempts.isEmpty && model.hasLoaded {
                Text("No requests recorded yet").foregroundStyle(.secondary)
            }
            ForEach(model.attempts) { RecordsAttemptRow(attempt: $0) }
        }
    }
}

private struct RecordsDaysSection: View {
    let days: [DayCollection]
    let collected: Int
    let missing: Int
    @State private var isExpanded = false

    var body: some View {
        Section {
            LabeledContent("Days airQ was opened", value: "\(collected)")
            LabeledContent("Days it wasn't opened", value: "\(missing)")
            DisclosureGroup("All days", isExpanded: $isExpanded) {
                ForEach(days) { day in
                    LabeledContent(day.dayKey) {
                        Text(day.isCollected ? "Opened" : "Not opened")
                            .foregroundStyle(day.isCollected ? Color.secondary : Color.orange)
                    }
                }
            }
        } header: {
            Text("Days")
        } footer: {
            Text("Days you didn't open airQ have no air quality record. That's a gap, not a reading of zero, and nothing to worry about.")
        }
    }
}

private struct RecordsCountsRows: View {
    let counts: RecordCounts

    var body: some View {
        Group {
            LabeledContent("Classifier windows", value: "\(counts.classifierWindows)")
            if counts.legacyDetections > 0 {
                LabeledContent("Legacy detections", value: "\(counts.legacyDetections)")
            }
            LabeledContent("Review verdicts", value: "\(counts.annotations)")
            LabeledContent("Provider requests", value: "\(counts.providerAttempts)")
            LabeledContent("Hourly air-quality rows", value: "\(counts.hourlyRows)")
        }
    }
}

private struct RecordsCoverageRow: View {
    let provider: String
    let coverage: HourlyCoverage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(RecordLabels.provider(provider)).fontWeight(.medium)
            if let earliest = coverage.earliest, let latest = coverage.latest {
                Text("\(coverage.distinctHours) hours · \(earliest.formatted(date: .abbreviated, time: .shortened)) – \(latest.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No hours stored yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecordsAttemptRow: View {
    let attempt: AttemptSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: attempt.status == "success" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(attempt.status == "success" ? .green : .orange)
                Text(RecordLabels.provider(attempt.provider)).fontWeight(.medium)
                Spacer()
                Text(attempt.requestedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let failure = attempt.failureDetail {
                Text(failure).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [RecordLabels.status(attempt.status)]
        if let code = attempt.httpStatus { parts.append("HTTP \(code)") }
        if let page = attempt.pageIndex { parts.append("page \(page + 1)") }
        if attempt.hourCount > 0 { parts.append("\(attempt.hourCount) hours") }
        return parts.joined(separator: " · ")
    }
}

enum RecordLabels {
    static func provider(_ raw: String) -> String {
        switch EnvironmentalProvider(rawValue: raw) {
        case .waqi: "WAQI air quality"
        case .googlePollen: "Google Pollen"
        case .googleAirQuality: "Google Air Quality"
        case nil: raw
        }
    }

    static func status(_ raw: String) -> String {
        switch EnvironmentalAttemptRecord.Status(rawValue: raw) {
        case .success: "Succeeded"
        case .httpError: "Provider returned an error"
        case .decodeError: "Response couldn't be read"
        case .missingData: "Response had no data"
        case .networkError: "Network unavailable"
        case .missingCredentials: "No API key configured"
        case .cancelled: "Cancelled"
        case .locationUnavailable: "Location unavailable"
        case .skippedBudget: "Skipped to stay within usage cap"
        case .notSent: "Not sent (offline)"
        case nil: raw
        }
    }
}

#Preview("Records") {
    NavigationStack { RecordsView(store: PreviewRecords()) }
}

private struct PreviewRecords: RecordReading {
    func dailyRecords() async throws -> [DailyRecordSnapshot] {
        let today = LocalDay(containing: .now, in: .current)
        return [today, today.previous.previous].map {
            DailyRecordSnapshot(dayKey: $0.key, dayStart: $0.interval.start, dayEnd: $0.interval.end,
                                timeZoneID: TimeZone.current.identifier, firstSeenAt: $0.interval.start)
        }
    }
    func providerRequestCount(provider: String, since date: Date) async throws -> Int { 12 }
    func recentAttempts(limit: Int) async throws -> [AttemptSummary] {
        [AttemptSummary(id: UUID(), provider: "waqi", requestKind: "current", status: "success", httpStatus: 200,
                        requestedAt: .now, failureDetail: nil, pageIndex: nil, hourCount: 0),
         AttemptSummary(id: UUID(), provider: "googleAirQuality", requestKind: "history", status: "httpError",
                        httpStatus: 400, requestedAt: .now.addingTimeInterval(-3_600),
                        failureDetail: "Invalid period", pageIndex: 0, hourCount: 0)]
    }
    func hourlyCoverage(provider: String) async throws -> HourlyCoverage {
        HourlyCoverage(rowCount: 700, distinctHours: 696, earliest: .now.addingTimeInterval(-30 * 86_400), latest: .now)
    }
    func recordCounts() async throws -> RecordCounts { RecordCounts() }
}
