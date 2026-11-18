import Foundation
import Observation
import SwiftData

/// Runs one export at a time and owns the archive it produces. The archive holds the whole record
/// unencrypted, so it is removed whenever the person leaves (`leave()`), and an export that finishes
/// after they left removes itself.
@MainActor @Observable
public final class ExportViewModel {
    public enum Phase {
        case idle, exporting
        case ready(URL, ExportManifest)
        case failed(String)
    }

    public private(set) var phase = Phase.idle
    public var isExporting: Bool { if case .exporting = phase { true } else { false } }

    private let container: ModelContainer
    private let appVersion: String
    private let folder: URL
    private let now: @Sendable () -> Date
    /// Called with the export time after a full (unlimited) export, the only kind that counts as a backup.
    private let didExportEverything: @MainActor (Date) -> Void
    /// A cancelled worker stays here until its filesystem work and cleanup have stopped.
    private var workers: [Int: Task<Void, Never>] = [:]
    private var generation = 0
    /// The plain-text summary of a period, written into the archive as summary.txt. Nil (or a nil result, e.g.
    /// the record store didn't open) exports without it. The date and bounds are shared with the CSV export.
    public var summaryProvider: (@MainActor (ExportPeriod, Date, DateInterval?) async -> String?)?

    public init(container: ModelContainer, appVersion: String,
                folder: URL = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory),
                now: @escaping @Sendable () -> Date = { Date() },
                didExportEverything: @escaping @MainActor (Date) -> Void) {
        self.container = container
        self.appVersion = appVersion
        self.folder = folder
        self.now = now
        self.didExportEverything = didExportEverything
    }

    /// Starts an export, replacing one still running.
    public func start(period: ExportPeriod) {
        _ = beginExport(period: period)
    }

    /// Runs an export to completion (used directly by launch-argument verification).
    public func run(period: ExportPeriod) async {
        guard !Task.isCancelled else { return }
        let worker = beginExport(period: period)
        await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }

    private func beginExport(period: ExportPeriod) -> Task<Void, Never> {
        leave()
        let mine = generation
        let directory = folder.appending(path: "airQ-export-run-\(UUID().uuidString)", directoryHint: .isDirectory)
        phase = .exporting
        let worker = Task { await export(period: period, generation: mine, directory: directory) }
        workers[mine] = worker
        return worker
    }

    private func export(period: ExportPeriod, generation mine: Int, directory: URL) async {
        var keepArchive = false
        defer {
            if !keepArchive { removeArchive(in: directory) }
            workers.removeValue(forKey: mine)
        }
        do {
            try Task.checkCancellation()
            let requestedAt = now()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let range = period.range(now: requestedAt, calendar: calendar)
            let summary = await summaryProvider?(period, requestedAt, range)
            try Task.checkCancellation()
            let exporter = await RecordExporter.open(container: container)
            try Task.checkCancellation()
            let result = try await exporter.exportArchive(into: directory, appVersion: appVersion, timeZone: calendar.timeZone,
                                                          now: requestedAt, range: range, summary: summary)
            try Task.checkCancellation()
            guard mine == generation else { return }
            keepArchive = true
            phase = .ready(result.zip, result.manifest)
            if period == .everything { didExportEverything(now()) }
        } catch {
            guard mine == generation else { return }
            if error is CancellationError || Task.isCancelled {
                phase = .idle
            } else {
                phase = .failed("Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func removeArchive(in directory: URL) {
        // Never remove the shared parent: another exporter can create its directory concurrently.
        try? FileManager.default.removeItem(at: directory)
    }

    /// A file made for one period must not stay on offer under another period's label.
    public func periodChanged() { leave() }

    /// The person left the screen: stop, and remove what was written.
    public func leave() {
        generation += 1
        for worker in workers.values { worker.cancel() }
        if case .ready(let zip, _) = phase { removeArchive(in: zip.deletingLastPathComponent()) }
        phase = .idle
    }

    /// Cancels export work and waits until it can no longer read records or create temporary files.
    public func cancelAndWait() async {
        leave()
        for worker in Array(workers.values) { await worker.value }
    }
}
