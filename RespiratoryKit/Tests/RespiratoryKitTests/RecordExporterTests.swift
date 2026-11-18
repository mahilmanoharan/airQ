import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import RespiratoryKit

@Suite("CSV export")
struct RecordExporterTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    /// Minimal RFC 4180 reader for verification.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\r\n" || c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private func populatedStore() async throws -> RecordExporter {
        let container = try RespiratoryStore.makeInMemoryContainer()
        let records = RecordStore(modelContainer: container)
        let detections = DetectionStore(modelContainer: container)
        var waqi = EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current", requestedAt: at,
                                              timeZoneID: zone.identifier, status: .success, parserVersion: 1, appVersion: "t")
        waqi.aqi = 42
        waqi.subIndices = ["pm25": 40, "t": 18.5]
        waqi.rawResponse = Data(#"{"status":"ok"}"#.utf8)
        try await records.record(waqi)
        var pollen = EnvironmentalAttemptRecord(provider: "googlePollen", requestKind: "forecast", requestedAt: at,
                                                timeZoneID: zone.identifier, status: .success, parserVersion: 1, appVersion: "t")
        pollen.pollenTypes = [.init(code: "GRASS", upi: 2, category: "Low", inSeason: true),
                              .init(code: "TREE", upi: nil, category: nil, inSeason: nil)]
        pollen.plants = [.init(code: "OAK", displayName: "Oak", upi: 1, category: "Very low", inSeason: true)]
        try await records.record(pollen)
        var history = EnvironmentalAttemptRecord(provider: "googleAirQuality", requestKind: "history", requestedAt: at,
                                                 timeZoneID: zone.identifier, status: .httpError, parserVersion: 1, appVersion: "t")
        history.rawResponse = Data("Bad Request".utf8)
        history.hours = [.init(hourStart: at, indexes: [.init(code: "uaqi", aqi: 60, category: "Good", dominantPollutant: "pm25")],
                               pollutants: nil)]
        try await records.record(history)
        try await records.appendContextEvent(ContextEventDraft(category: "other", note: "said \"hi\", then\nleft",
                                                               startDayKey: "2026-09-20", endDayKey: nil),
                                             supersedes: nil, isRetraction: false, recordedAt: at, timeZone: zone, appVersion: "t")
        try await records.appendCheckIn(CheckInDraft(dayKey: "2026-09-21", daytimeSymptoms: true, daytimeSeverity: 2,
                                                     symptomsSelected: ["cough", "wheeze"]),
                                        recordedAt: at, timeZone: zone, completionSeconds: 4.2, appVersion: "t")
        let stream = AsyncThrowingStream<CaptureEvent, any Error> { continuation in
            continuation.yield(.started(at))
            continuation.yield(.window(WindowObservation(windowIndex: 0, startFrame: 16_000, durationFrames: 16_000, deliveredAt: at,
                                                         scores: [0.7, .nan], topLabels: ["cough"], topScores: [0.7], rms: 0.01, peak: 0.2)))
            continuation.finish()
        }
        let info = CaptureSessionInfo(requestedAt: at, timeZoneID: zone.identifier, sampleRate: 16_000, channelCount: 1,
                                      tapBufferSize: 4096, inputPortType: nil, inputPortName: nil, classifierIdentifier: "version1",
                                      windowDuration: 1, overlapFactor: 0.5, scoredLabels: ["cough", "speech"], topK: 3,
                                      captureSemanticsVersion: 2, osVersion: "t", deviceModel: "t")
        _ = await detections.beginIngest(info, appVersion: "t", events: stream, stopRequest: .init(), stopCapture: {}).value
        let window = try #require(try await detections.candidates(label: "cough", in: nil).first)
        try await detections.annotate(window, verdict: .confirmed, source: "review", note: nil, at: at, appVersion: "t")
        try await detections.recordLegacy(sessionID: UUID(), label: "sneeze", confidence: 0.3, timestamp: at,
                                          config: DetectionConfig(windowDuration: 1, overlapFactor: 0.5,
                                                                  classifierIdentifier: "version1", appVersion: "1.0 (2)"))
        return RecordExporter(modelContainer: container)
    }

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "airq-export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func table(_ folder: URL, _ name: String) throws -> [[String: String]] {
        let rows = Self.parse(try String(contentsOf: folder.appending(path: name), encoding: .utf8))
        let header = try #require(rows.first)
        return rows.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
    }

    @Test("Every table exports every row, and every column is in the data dictionary")
    func completeness() async throws {
        let exporter = try await populatedStore()
        let (folder, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "1.0 (3)", timeZone: zone, now: at)
        let dictionary = try table(folder, "data_dictionary.csv")
        let documented = Set(dictionary.map { "\($0["file"] ?? "")/\($0["column"] ?? "")" })
        for file in manifest.files where file.name.hasSuffix(".csv") && file.name != "data_dictionary.csv" {
            let rows = Self.parse(try String(contentsOf: folder.appending(path: file.name), encoding: .utf8))
            let header = try #require(rows.first)
            for column in header { #expect(documented.contains("\(file.name)/\(column)"), "\(file.name)/\(column)") }
            #expect(rows.count - 1 == file.rows, "\(file.name)")
            #expect(rows.allSatisfy { $0.count == header.count }, "\(file.name) ragged")
        }
        let counts = Dictionary(uniqueKeysWithValues: manifest.files.compactMap { f in f.rows.map { (f.name, $0) } })
        #expect(counts["environmental_observations.csv"] == 3)
        #expect(counts["listening_sessions.csv"] == 1 && counts["classifier_windows.csv"] == 1)
        #expect(counts["legacy_detection_events.csv"] == 1 && counts["detection_annotations.csv"] == 1)
        #expect(counts["hourly_air_quality.csv"] == 1 && counts["pollen_plants.csv"] == 1)
        #expect(counts["daily_check_ins.csv"] == 1 && counts["context_events.csv"] == 1)
        #expect(counts["daily_records.csv"] == 1)
    }

    @Test("Values round-trip: escaping, nulls stay empty, NaN is explicit, times carry offset and epoch")
    func values() async throws {
        let exporter = try await populatedStore()
        let (folder, _) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        #expect(try table(folder, "context_events.csv").first?["note"] == "said \"hi\", then\nleft")

        let windows = try table(folder, "classifier_windows.csv")
        #expect(windows.first?["score_cough"] == String(Double(Float(0.7))))
        #expect(windows.first?["score_speech"] == "NaN")
        #expect(windows.first?["window_start_epoch"] == "1790000001.000")
        #expect(windows.first?["window_start"] == "2026-09-21T07:13:21.000-07:00")

        let observations = try table(folder, "environmental_observations.csv")
        let pollen = try #require(observations.first { $0["provider"] == "googlePollen" })
        #expect(pollen["pollen_grass_upi"] == "2" && pollen["pollen_tree_upi"] == "")
        let waqi = try #require(observations.first { $0["provider"] == "waqi" })
        #expect(waqi["iaqi_pm25"] == "40.0" && waqi["iaqi_t"] == "18.5" && waqi["received_at"] == "")
        #expect(waqi["raw_response_file"]?.hasSuffix(".json") == true)
        let failed = try #require(observations.first { $0["provider"] == "googleAirQuality" })
        #expect(failed["raw_response_file"]?.hasSuffix(".txt") == true)

        let checkIn = try #require(try table(folder, "daily_check_ins.csv").first)
        #expect(checkIn["symptoms_selected"] == "cough|wheeze" && checkIn["night_waking"] == "")
        #expect(try table(folder, "hourly_air_quality.csv").first?["index_uaqi_aqi"] == "60")
    }

    @Test("A bare CRLF inside a note stays in one CSV cell")
    func embeddedCRLF() async throws {
        let container = try RespiratoryStore.makeInMemoryContainer()
        let store = RecordStore(modelContainer: container)
        let note = "first line\r\nsecond line"
        try await store.appendContextEvent(.init(category: "other", note: note, startDayKey: "2026-09-21", endDayKey: nil),
                                           supersedes: nil, isRetraction: false, recordedAt: at, timeZone: zone, appVersion: "t")
        let parent = try tempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let (folder, _) = try await RecordExporter(modelContainer: container).export(into: parent, appVersion: "t")
        let rows = try table(folder, "context_events.csv")
        #expect(rows.count == 1)
        #expect(rows.first?["note"] == note)
    }

    @Test("CSV text escapes spreadsheet formula prefixes and preserves literal apostrophes and numeric values")
    func spreadsheetCells() throws {
        let parent = try tempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let writer = try CSVFileWriter(directory: parent, fileName: "cells.csv", columns: [
            CSVColumn("note", "text", "A note."), CSVColumn("labels", "list", "Labels."),
            CSVColumn("latitude", "number", "Signed latitude."),
        ])
        try writer.write([" =1+1", "@name|second", "-42.5"])
        try writer.write(["'quoted", "", ""])
        try writer.write(["\tordinary", "", ""])
        try writer.write(["＋1", "", ""])
        _ = try writer.finish()
        let csv = try String(contentsOf: parent.appending(path: "cells.csv"), encoding: .utf8)
        #expect(Self.parse(csv) == [
            ["note", "labels", "latitude"], ["' =1+1", "'@name|second", "-42.5"],
            ["''quoted", "", ""], ["'\tordinary", "", ""], ["'＋1", "", ""],
        ])
    }

    @Test("A cancelled archive never removes an earlier export or writes a new file")
    func cancelledArchive() async throws {
        let exporter = try await populatedStore()
        let parent = try tempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let previous = parent.appending(path: "airQ-export-previous.zip")
        try Data("previous".utf8).write(to: previous)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await exporter.exportArchive(into: parent, appVersion: "t")
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["airQ-export-previous.zip"])
    }

    @Test("A CSV writer observes cancellation while emitting rows")
    func cancelledCSV() async throws {
        let parent = try tempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let cancelled = Task {
            let writer = try CSVFileWriter(directory: parent, fileName: "rows.csv", columns: [
                CSVColumn("note", "text", "A note."),
            ])
            try writer.write(["first"])
            withUnsafeCurrentTask { $0?.cancel() }
            try writer.write(["second"])
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    @Test("The manifest hashes each file's exact bytes, and the folder zips")
    func manifestAndZip() async throws {
        let exporter = try await populatedStore()
        let (folder, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        #expect(manifest.files.contains { $0.name.hasPrefix("raw/") })
        for file in manifest.files {
            let data = try Data(contentsOf: folder.appending(path: file.name))
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == file.sha256, "\(file.name)")
        }
        let decoded = try JSONDecoder().decode(ExportManifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
        #expect(decoded == manifest)
        let zip = try ExportArchive.zip(folder)
        #expect(try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 > 0)
    }

    @Test("Rows tied on the sort key page deterministically: 1,200 identical hours export exactly once each")
    func tiedRowsPageExactly() async throws {
        let container = try RespiratoryStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let hour = Date(timeIntervalSince1970: 1_790_000_000)
        let observation = UUID()
        for _ in 0..<1_200 {
            context.insert(HourlyAirQuality(observationID: observation, provider: "googleAirQuality", hourStart: hour,
                                            indexes: nil, pollutants: nil))
        }
        try context.save()
        let (folder, manifest) = try await RecordExporter(modelContainer: container)
            .export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        #expect(manifest.files.first { $0.name == "hourly_air_quality.csv" }?.rows == 1_200)
        let ids = try table(folder, "hourly_air_quality.csv").compactMap { $0["id"] }
        #expect(Set(ids).count == 1_200)
    }

    @Test("README.txt describes every exported file with its row count, the versions and every note")
    func readme() async throws {
        let exporter = try await populatedStore()
        let (folder, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "1.0 (4)", timeZone: zone, now: at)
        let readme = try String(contentsOf: folder.appending(path: "README.txt"), encoding: .utf8)
        for file in manifest.files where !file.name.hasPrefix("raw/") {
            #expect(RecordExporter.tableDescriptions[file.name] != nil, "no description for \(file.name)")
            #expect(readme.contains("\(file.name) (\(file.rows ?? -1) rows)"), "\(file.name)")
        }
        for note in manifest.notes { #expect(readme.contains(note)) }
        #expect(readme.contains("check-in questions set \(CheckInQuestionSet.version)"))
        #expect(readme.contains("app 1.0 (4)"))
        #expect(readme.contains("raw/ (\(manifest.files.count { $0.name.hasPrefix("raw/") }) files)"))
    }

    @Test("A summary is written as summary.txt, hashed in the manifest and described in the README; none, no file")
    func summaryFile() async throws {
        let exporter = try await populatedStore()
        let text = "airQ summary\nCheck-ins: 3 of 7 days"
        let (folder, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at,
                                                           summary: text)
        let entry = try #require(manifest.files.first { $0.name == "summary.txt" })
        let data = try Data(contentsOf: folder.appending(path: "summary.txt"))
        #expect(String(decoding: data, as: UTF8.self) == text)
        #expect(entry.rows == nil)
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == entry.sha256)
        let readme = try String(contentsOf: folder.appending(path: "README.txt"), encoding: .utf8)
        #expect(readme.contains("summary.txt\n    \(try #require(RecordExporter.tableDescriptions["summary.txt"]))"))

        let (plain, plainManifest) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        #expect(!plainManifest.files.contains { $0.name == "summary.txt" })
        #expect(!FileManager.default.fileExists(atPath: plain.appending(path: "summary.txt").path(percentEncoded: false)))
    }

    private func counts(_ manifest: ExportManifest) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: manifest.files.compactMap { file in file.rows.map { (file.name, $0) } })
    }

    @Test("A range containing the data exports exactly what an unlimited export does, and says which range")
    func rangeContainingEverything() async throws {
        let exporter = try await populatedStore()
        let day = LocalDay(containing: at, in: zone).interval
        let (_, full) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        let (folder, limited) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at, range: day)
        #expect(counts(limited) == counts(full))
        #expect(limited.rangeStart != nil && limited.rangeEnd != nil && full.rangeStart == nil)
        #expect(limited.notes.contains(RecordExporter.rangeNote) && !full.notes.contains(RecordExporter.rangeNote))
        let readme = try String(contentsOf: folder.appending(path: "README.txt"), encoding: .utf8)
        #expect(readme.contains("Limited to rows recorded from"))
    }

    @Test("A range that misses the data leaves every table empty but still complete and documented")
    func rangeMissingEverything() async throws {
        let exporter = try await populatedStore()
        // The day before: the fixture's session was closed at the real "now", so it overlaps any later range.
        let dayBefore = LocalDay(containing: at, in: zone).previous.interval
        let (folder, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at, range: dayBefore)
        let tables = manifest.files.filter { $0.name.hasSuffix(".csv") && $0.name != "data_dictionary.csv" }
        #expect(tables.count == 10 && tables.allSatisfy { $0.rows == 0 })
        #expect(manifest.files.filter { $0.name.hasPrefix("raw/") }.isEmpty)
        #expect(try table(folder, "data_dictionary.csv").count > 50)
        let readme = try String(contentsOf: folder.appending(path: "README.txt"), encoding: .utf8)
        #expect(readme.contains("Limited to rows recorded from"))
    }

    @Test("A session that began before the range but ran into it is exported with its windows")
    func sessionOverlappingRangeStart() async throws {
        let container = try RespiratoryStore.makeInMemoryContainer()
        let detections = DetectionStore(modelContainer: container)
        let start = at, end = at.addingTimeInterval(1_800)
        let stream = AsyncThrowingStream<CaptureEvent, any Error> { continuation in
            continuation.yield(.started(start))
            continuation.yield(.window(WindowObservation(windowIndex: 0, startFrame: 0, durationFrames: 16_000, deliveredAt: end,
                                                         scores: [0.7], topLabels: ["cough"], topScores: [0.7], rms: 0.01, peak: 0.2)))
            continuation.finish()
        }
        let info = CaptureSessionInfo(requestedAt: start, timeZoneID: zone.identifier, sampleRate: 16_000, channelCount: 1,
                                      tapBufferSize: 4096, inputPortType: nil, inputPortName: nil, classifierIdentifier: "version1",
                                      windowDuration: 1, overlapFactor: 0.5, scoredLabels: ["cough"], topK: 3,
                                      captureSemanticsVersion: 2, osVersion: "t", deviceModel: "t")
        _ = await detections.beginIngest(info, appVersion: "t", events: stream, stopRequest: .init(), stopCapture: {}).value
        // The range starts after the session began but before its window was delivered.
        let range = DateInterval(start: at.addingTimeInterval(900), end: at.addingTimeInterval(3_600))
        let (_, manifest) = try await RecordExporter(modelContainer: container)
            .export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: end, range: range)
        let rows = counts(manifest)
        #expect(rows["classifier_windows.csv"] == 1)
        #expect(rows["listening_sessions.csv"] == 1, "the window's session must be present so the join works")
    }

    @Test("Every column added after schema 2 is dictionary-marked with its schema version")
    func dictionaryDatesTheAdherenceColumn() async throws {
        let (folder, _) = try await populatedStore().export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        let entry = try #require(try table(folder, "data_dictionary.csv").first {
            $0["file"] == "daily_check_ins.csv" && $0["column"] == "controller_adherence"
        })
        #expect(entry["since_schema"] == "3")
    }

    @Test("The archive step removes only earlier exports from its folder, never anything else")
    func archiveLeavesOtherFilesAlone() async throws {
        let parent = try tempFolder()
        let unrelated = parent.appending(path: "keep-me.txt")
        try Data("mine".utf8).write(to: unrelated)
        let stale = parent.appending(path: "airQ-export-old.zip")
        try Data("old".utf8).write(to: stale)
        let exporter = try await populatedStore()
        let (zip, _) = try await exporter.exportArchive(into: parent, appVersion: "t")
        #expect(FileManager.default.fileExists(atPath: unrelated.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: zip.path(percentEncoded: false)))
        // The unpacked folder is removed once zipped.
        let names = try FileManager.default.contentsOfDirectory(atPath: parent.path(percentEncoded: false))
        #expect(names.filter { $0.hasPrefix("airQ-export-") }.allSatisfy { $0.hasSuffix(".zip") })
    }

    @Test("An open-ended export stops at the moment it starts, so later writes can't shift its pages")
    func openEndedExportHasACutoff() async throws {
        let exporter = try await populatedStore()
        // A request stamped in the future stands for one recorded after the export began.
        let container = exporter.modelContainer
        let records = RecordStore(modelContainer: container)
        try await records.record(EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current",
                                                            requestedAt: Date().addingTimeInterval(3_600), timeZoneID: zone.identifier,
                                                            status: .success, parserVersion: 1, appVersion: "t"))
        let (_, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        #expect(counts(manifest)["environmental_observations.csv"] == 3, "the 'future' request is after the cutoff")
        #expect(manifest.rangeStart == nil, "still an unlimited export, not a limited one")
    }

    @Test("The end of a range is exclusive and its start inclusive")
    func rangeEdges() async throws {
        let exporter = try await populatedStore()
        let day = LocalDay(containing: at, in: zone).interval
        let endsAtData = DateInterval(start: day.start, end: at)
        let startsAtData = DateInterval(start: at, end: day.end)
        let (_, before) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at, range: endsAtData)
        let (_, after) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at, range: startsAtData)
        #expect(counts(before)["environmental_observations.csv"] == 0)
        #expect(counts(after)["environmental_observations.csv"] == 3)
    }

    @Test("An empty store still exports headers and a complete dictionary")
    func emptyStore() async throws {
        let exporter = RecordExporter(modelContainer: try RespiratoryStore.makeInMemoryContainer())
        let (_, manifest) = try await exporter.export(into: try tempFolder(), appVersion: "t", timeZone: zone, now: at)
        #expect(manifest.files.filter { $0.name.hasSuffix(".csv") }.count == 11)  // 10 tables + data_dictionary
        #expect(manifest.files.allSatisfy { $0.rows != nil || $0.name.hasPrefix("raw/") })
    }
}
