import CryptoKit
import Foundation
import SwiftData

public struct ExportManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public let name: String
        public let rows: Int?
        public let sha256: String
    }

    public let exportedAt: String
    public let exportedAtEpoch: Double
    public let deviceTimeZone: String
    public let appVersion: String
    public let schemaVersion: Int
    public let captureSemanticsVersion: Int
    public let analysisRulesVersion: Int
    public let checkInQuestionSetVersion: Int
    public let files: [File]
    public let notes: [String]
    /// The range this export was limited to (ISO 8601, UTC); nil when it covers everything.
    public let rangeStart: String?
    public let rangeEnd: String?
}

public enum ExportError: LocalizedError, Sendable, Equatable {
    case incomplete(table: String, expected: Int, exported: Int)
    case duplicateRow(table: String)

    public var errorDescription: String? {
        switch self {
        case .incomplete(let table, let expected, let exported):
            "Export stopped: \(table) wrote \(exported) of \(expected) rows. Try again."
        case .duplicateRow(let table): "Export stopped: \(table) repeated a row. Try again."
        }
    }
}

/// Writes the whole record as CSV (one file per table), raw provider bodies, a data dictionary and a
/// manifest. Runs on its own executor with batched fetches through short-lived contexts, so memory
/// stays bounded however much history exists. Nothing is filtered, thresholded or aggregated;
/// derived columns are marked as such in the dictionary.
@ModelActor
public actor RecordExporter {
    static let batchSize = 500

    @concurrent
    public static func open(container: ModelContainer) async -> RecordExporter {
        RecordExporter(modelContainer: container)
    }

    /// Exports into a new folder inside `parent` and returns that folder and its manifest.
    /// With a `range`, only rows *recorded* inside it are written (a session or window by when it
    /// happened, a provider request by when it was made, a check-in, label or context event by when
    /// it was saved), so a person can share a recent stretch instead of their whole history. `nil`
    /// exports everything.
    public func export(into parent: URL, appVersion: String, timeZone: TimeZone = .current,
                       now: Date = Date(), range: DateInterval? = nil,
                       summary: String? = nil) throws -> (folder: URL, manifest: ExportManifest) {
        try Task.checkCancellation()
        let format = CSVFormat(timeZone: timeZone)
        // Open-ended exports stop at the moment they start: the app keeps recording while a large export
        // runs, and rows stamped after this instant would otherwise shift the pages and the counts.
        let bounds = range ?? DateInterval(start: .distantPast, end: max(now, Date()))
        let stamp = now.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().dateSeparator(.omitted)
            .time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = parent.appending(path: "airQ-export-\(stamp)", directoryHint: .isDirectory)
        let raw = folder.appending(path: "raw", directoryHint: .isDirectory)
        let manager = FileManager.default
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        var isComplete = false
        defer { if !isComplete { try? manager.removeItem(at: folder) } }
        try manager.createDirectory(at: raw, withIntermediateDirectories: false)

        var files: [ExportManifest.File] = []
        var dictionary: [(file: String, column: CSVColumn)] = []
        func finish(_ writer: CSVFileWriter) throws {
            files.append(.init(name: writer.fileName, rows: writer.rowCount, sha256: try writer.finish()))
            dictionary += writer.columns.map { (writer.fileName, $0) }
        }

        try finish(try stable { try exportSessions(folder, format, bounds) })
        try finish(try stable { try exportWindows(folder, format, bounds) })
        try finish(try stable { try exportLegacyEvents(folder, format, bounds) })
        try finish(try stable { try exportAnnotations(folder, format, bounds) })
        try finish(try stable { try exportDailyRecords(folder, format, bounds) })
        let (observations, plants, rawFiles) = try stable { try exportObservations(folder, raw, format, bounds) }
        try finish(observations)
        try finish(plants)
        try finish(try stable { try exportHourly(folder, format, bounds) })
        try finish(try stable { try exportCheckIns(folder, format, bounds) })
        try finish(try stable { try exportContextEvents(folder, format, bounds) })
        files += rawFiles

        let dictionaryWriter = try CSVFileWriter(directory: folder, fileName: "data_dictionary.csv", columns: [
            CSVColumn("file", "text", "CSV file name."), CSVColumn("column", "text", "Column name."),
            CSVColumn("type", "text", "text, integer, number, boolean, timestamp or list (pipe-separated)."),
            CSVColumn("unit", "text", null: "no unit", "Unit or format."),
            CSVColumn("null_meaning", "text", "What an empty cell means."),
            CSVColumn("description", "text", "Meaning and source."),
            CSVColumn("since_schema", "integer", "First schema version with this column."),
        ])
        for entry in dictionary {
            try dictionaryWriter.write([entry.file, entry.column.name, entry.column.type, entry.column.unit,
                                        entry.column.nullMeaning, entry.column.description,
                                        String(entry.column.sinceSchema)])
        }
        let dictionaryRows = dictionaryWriter.rowCount
        files.append(.init(name: "data_dictionary.csv", rows: dictionaryRows, sha256: try dictionaryWriter.finish()))
        try Task.checkCancellation()
        if let summary {
            let data = Data(summary.utf8)
            try data.write(to: folder.appending(path: "summary.txt"))
            files.append(.init(name: "summary.txt", rows: nil,
                               sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
        }

        let manifest = ExportManifest(
            exportedAt: now.formatted(Date.ISO8601FormatStyle(timeZone: .gmt)), exportedAtEpoch: now.timeIntervalSince1970,
            deviceTimeZone: timeZone.identifier, appVersion: appVersion, schemaVersion: RespiratoryStore.schemaVersion,
            captureSemanticsVersion: CaptureLabels.captureSemanticsVersion,
            analysisRulesVersion: DetectionAnalysis.rulesVersion, checkInQuestionSetVersion: CheckInQuestionSet.version,
            files: files, notes: Self.notes + (range == nil ? [] : [Self.rangeNote]),
            rangeStart: range.map { $0.start.formatted(Date.ISO8601FormatStyle(timeZone: .gmt)) },
            rangeEnd: range.map { $0.end.formatted(Date.ISO8601FormatStyle(timeZone: .gmt)) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Task.checkCancellation()
        try encoder.encode(manifest).write(to: folder.appending(path: "manifest.json"))
        try Task.checkCancellation()
        try Data(Self.readme(for: manifest).utf8).write(to: folder.appending(path: "README.txt"))
        try Task.checkCancellation()
        isComplete = true
        return (folder, manifest)
    }

    /// The app keeps writing while an export runs (a provider attempt, a listening window), so a table
    /// can come out one row off its count. That is a moving target, not a broken export: write the
    /// table again, a few times, and only fail if it never settles.
    private func stable<T>(_ write: () throws -> T) throws -> T {
        var failure: ExportError?
        for _ in 0..<3 {
            do { return try write() } catch let error as ExportError { failure = error }
        }
        throw failure ?? ExportError.incomplete(table: "unknown", expected: 0, exported: 0)
    }

    /// One line per exported table, for README.txt. Every exported file must have an entry.
    static let tableDescriptions: [String: String] = [
        "listening_sessions.csv": "One row per Start→Stop listening session: timing, why it ended, device/input and capture settings.",
        "classifier_windows.csv": "Every analysed audio window: per-label classifier scores, top labels and loudness. Audio itself is never stored.",
        "legacy_detection_events.csv": "Detections from builds 1–2, which kept only windows above a threshold.",
        "detection_annotations.csv": "The user's review verdicts on windows (append-only; the latest per window and label is current).",
        "daily_records.csv": "One row per local day airQ was opened. A missing day was not collected.",
        "environmental_observations.csv": "Every air-quality and pollen request, including failures and skipped requests, with parsed values.",
        "pollen_plants.csv": "Per-plant pollen values from each Google Pollen answer.",
        "hourly_air_quality.csv": "Google Air Quality hourly index history (indexes only, no concentrations).",
        "daily_check_ins.csv": "Daily check-ins (append-only; the latest per day is current). Compare within a question_set_version.",
        "context_events.csv": "Medication changes, illness, travel and moves (append-only; see supersedes_id and is_retraction).",
        "data_dictionary.csv": "Every column of every table: type, unit, what an empty cell means, and a description.",
        "summary.txt": "A plain-text recap in whole days. A limited export summarizes only life-event and check-in entries saved within its date range. The CSVs contain the underlying rows.",
    ]

    /// A plain-text overview for whoever receives the export (a clinician or statistician).
    /// Generated from the manifest, so versions, files and row counts always match the data.
    static func readme(for manifest: ExportManifest) -> String {
        var lines = [
            "airQ data export",
            "================",
            "",
            "Exported \(manifest.exportedAt) (device time zone \(manifest.deviceTimeZone)), app \(manifest.appVersion).",
            "Record schema \(manifest.schemaVersion) · capture semantics \(manifest.captureSemanticsVersion) · "
                + "analysis rules \(manifest.analysisRulesVersion) · check-in questions set \(manifest.checkInQuestionSetVersion).",
            manifest.rangeStart.map { start in
                "Limited to rows recorded from \(start) to \(manifest.rangeEnd ?? "now"); older and newer rows are not included."
            } ?? "Covers everything airQ had recorded on this device when the export started.",
            "",
            "This is a descriptive record of air quality, pollen and self-reported symptoms. airQ does not diagnose,",
            "score or infer anything; interpretation is up to the reader.",
            "",
            "Files",
            "-----",
        ]
        let rawCount = manifest.files.count { $0.name.hasPrefix("raw/") }
        for file in manifest.files where !file.name.hasPrefix("raw/") {
            let rows = file.rows.map { " (\($0) rows)" } ?? ""
            lines.append("\(file.name)\(rows)")
            if let description = tableDescriptions[file.name] { lines.append("    \(description)") }
        }
        lines += [
            "raw/ (\(rawCount) files)",
            "    Verbatim provider response bodies, named by attempt id (environmental_observations.id).",
            "manifest.json",
            "    Versions and a SHA-256 hash of every file above, for checking the export is complete and unchanged.",
            "",
            "Reading the data",
            "----------------",
        ]
        lines += manifest.notes.map { "- \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Exports and zips on this actor, replacing earlier exports in `parent` (they're copies).
    public func exportArchive(into parent: URL, appVersion: String, timeZone: TimeZone = .current,
                              now: Date = Date(), range: DateInterval? = nil,
                              summary: String? = nil) throws -> (zip: URL, manifest: ExportManifest) {
        try Task.checkCancellation()
        let manager = FileManager.default
        // Only this feature's own leftovers go: `parent` may hold anything else.
        for item in (try? manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent.hasPrefix("airQ-export-") {
            try Task.checkCancellation()
            try? manager.removeItem(at: item)
        }
        let (folder, manifest) = try export(into: parent, appVersion: appVersion, timeZone: timeZone, now: now,
                                            range: range, summary: summary)
        defer { try? manager.removeItem(at: folder) }
        return (try ExportArchive.zip(folder), manifest)
    }

    static let rangeNote = "This export is limited to a date range (rangeStart to rangeEnd in manifest.json). Each row is included by when it was recorded: windows by when they were delivered and sessions when they overlap the range, provider requests by when they were made, and check-ins, labels and context events by when they were saved. Rows outside the range are not here, so an ongoing context event recorded earlier, or a label saved later for a window inside the range, may be missing."

    static let notes = [
        "Timestamps are ISO 8601 with the export device's UTC offset, plus a *_epoch column in Unix seconds.",
        "An empty cell is null; data_dictionary.csv gives each column's null meaning. Lists are pipe-separated.",
        "Rows are raw observations. Nothing is thresholded or aggregated; debounce/bout rules are not applied.",
        "CSV text and list fields use a reversible leading apostrophe to protect formula-like text, including values that already start with an apostrophe. Import these columns as text. To recover the original values, parse the original CSV and remove exactly one leading apostrophe from any text or list cell that starts with one, before splitting lists. Numeric values and the original provider bodies are unchanged.",
        "Tables join on UUID columns (session_id, observation_id, target_*_id) and day_key.",
        "A day with no daily_records row was not collected. A day whose observations all failed was collected with no data.",
        "Environmental exposure is where the phone was when airQ asked, not continuous personal exposure.",
        "WAQI iaqi_* values are per-pollutant AQI sub-indices (plus weather t/h/p/w), not concentrations. WAQI's aqi scale is not documented by its API (it appears US-EPA-like; unverified).",
        "Google Pollen values are forecasts, not measurements; forecast_date is the provider's UTC-based date. Parsed pollen columns are the first forecast day only; requests with request_parameters {\"days\":5} also carry four later days in the raw body.",
        "Google Air Quality history rows carry indexes (uaqi, usa_epa) but no pollutant concentrations.",
        "Audio is never stored, so classifier windows cannot be re-scored by a future model.",
        "Check-ins resemble but are not a validated instrument; compare answers only within a question_set_version. Version 2 adds controller_adherence and leaves every version-1 question unchanged.",
        "A check-in with an empty completion_seconds was saved without the form: \"No symptoms today\" from Siri or Shortcuts, which answers only the symptom questions and keeps the day's other answers.",
    ]
}

public enum ExportArchive {
    /// Zips `folder` with the system archiver (NSFileCoordinator's `.forUploading`) and moves the zip
    /// next to it. Returns the zip's URL.
    public static func zip(_ folder: URL) throws -> URL {
        try Task.checkCancellation()
        let destination = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".zip")
        let manager = FileManager.default
        try? manager.removeItem(at: destination)
        var coordinationError: NSError?
        var moveError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try Task.checkCancellation()
                try manager.moveItem(at: zipped, to: destination)
            } catch { moveError = error }
        }
        if Task.isCancelled {
            try? manager.removeItem(at: destination)
            throw CancellationError()
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
        return destination
    }
}
