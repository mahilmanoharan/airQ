import CryptoKit
import Foundation
import SwiftData

/// Listening sessions, classifier windows, legacy detections and review verdicts.
extension RecordExporter {
    func exportSessions(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end  // A session is included if it overlaps the range (its windows join to it); one that never closed counts as its start.
        let writer = try CSVFileWriter(directory: folder, fileName: "listening_sessions.csv", columns: [
            CSVColumn("id", "text", "Session UUID; joins classifier_windows.session_id."),
        ] + CSVColumn.timestamp("started_at", "Wall clock at the first audio buffer (or at start if no audio arrived).")
          + CSVColumn.timestamp("ended_at", null: "session never closed cleanly (app quit or crashed); the last window bounds it",
                                "When the session was closed.") + [
            CSVColumn("end_reason", "text", null: "session never closed cleanly",
                      ListeningEndReason.allCases.map(\.rawValue).joined(separator: ", ")
                          + ". Some sound checks may be missing after a flushTimedOut."),
            CSVColumn("time_zone_id", "text", "Device time zone when the session started."),
            CSVColumn("sample_rate", "number", unit: "Hz", "Input sample rate; converts frames to seconds."),
            CSVColumn("channel_count", "integer", "Input channels."),
            CSVColumn("tap_buffer_size", "integer", unit: "frames", "Requested audio tap buffer size."),
            CSVColumn("input_port_type", "text", null: "not reported", "Audio input route (e.g. MicrophoneBuiltIn, BluetoothHFP)."),
            CSVColumn("input_port_name", "text", null: "not reported", "Input device name."),
            CSVColumn("classifier_identifier", "text", "SoundAnalysis classifier (version1)."),
            CSVColumn("window_duration", "number", unit: "seconds", "Classifier analysis window length."),
            CSVColumn("overlap_factor", "number", "Fraction of each window overlapping the next."),
            CSVColumn("scored_labels", "list", "Labels scored in every window, in order."),
            CSVColumn("top_k", "integer", "How many top-ranked labels each window stores."),
            CSVColumn("capture_semantics_version", "integer", "2 = every window stored with per-label scores."),
            CSVColumn("app_version", "text", "App version (build)."),
            CSVColumn("os_version", "text", "Operating system version."),
            CSVColumn("device_model", "text", "Hardware model identifier."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ])
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<ListeningSession>(predicate: #Predicate<ListeningSession> { $0.startedAt < hi && ($0.endedAt ?? $0.startedAt) >= lo }, sortBy: [SortDescriptor(\.startedAt), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                try writer.write([row.id.uuidString] + f.timestamp(row.startedAt) + f.timestamp(row.endedAt) + [
                    f.text(row.endReason), row.timeZoneID, f.number(row.sampleRate), f.int(row.channelCount),
                    f.int(row.tapBufferSize), f.text(row.inputPortType), f.text(row.inputPortName),
                    row.classifierIdentifier, f.number(row.windowDuration), f.number(row.overlapFactor),
                    f.list(row.scoredLabels), f.int(row.topK), f.int(row.captureSemanticsVersion), row.appVersion,
                    row.osVersion, row.deviceModel, f.int(row.schemaVersion)])
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<ListeningSession>(predicate: #Predicate<ListeningSession> { $0.startedAt < hi && ($0.endedAt ?? $0.startedAt) >= lo })))
        return writer
    }

    func exportWindows(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        let context = ModelContext(modelContainer)
        let sessions = try context.fetch(FetchDescriptor<ListeningSession>())
        let sessionsByID = Dictionary(sessions.map { ($0.id, (start: $0.startedAt, rate: $0.sampleRate, labels: $0.scoredLabels)) },
                                      uniquingKeysWith: { first, _ in first })
        var labels = CaptureLabels.scored
        for session in sessions { labels += session.scoredLabels.filter { !labels.contains($0) } }
        let used = Set(sessions.flatMap(\.scoredLabels))
        labels = labels.filter(used.contains)

        let writer = try CSVFileWriter(directory: folder, fileName: "classifier_windows.csv", columns: [
            CSVColumn("id", "text", "Window UUID; joins detection_annotations.target_window_id."),
            CSVColumn("session_id", "text", "Joins listening_sessions.id."),
            CSVColumn("window_index", "integer", "Order within the session, from 0."),
            CSVColumn("start_frame", "integer", unit: "frames", "Window start, frames since the session's first buffer."),
            CSVColumn("duration_frames", "integer", unit: "frames", "Window length in frames."),
        ] + CSVColumn.timestamp("window_start", null: "session missing",
                                "Derived: session started_at + start_frame / sample_rate.")
          + CSVColumn.timestamp("delivered_at", "When the classifier delivered the result (lags audio time).") + [
            CSVColumn("top_labels", "list", "Top-ranked labels, best first."),
            CSVColumn("top_scores", "list", unit: "0–1", "Scores of top_labels, same order."),
            CSVColumn("rms", "number", unit: "linear amplitude 0–1", null: "not measurable", "Input RMS over the window (ambient level covariate)."),
            CSVColumn("peak", "number", unit: "linear amplitude 0–1", null: "not measurable", "Peak absolute sample over the window."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ] + labels.map {
            CSVColumn("score_\($0)", "number", unit: "0–1",
                      null: "label not scored in this window's session; NaN = classifier returned no score",
                      "Classifier score for \($0), at any rank, unthresholded.")
        })
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<ClassifierWindow>(predicate: #Predicate<ClassifierWindow> { $0.deliveredAt >= lo && $0.deliveredAt < hi }, sortBy: [SortDescriptor(\.deliveredAt), SortDescriptor(\.startFrame), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                let session = sessionsByID[row.sessionID]
                let start = session.map { $0.start.addingTimeInterval(Double(row.startFrame) / max($0.rate, 1)) }
                let scores = labels.map { label -> String in
                    guard let index = session?.labels.firstIndex(of: label), index < row.scores.count else { return "" }
                    return f.number(row.scores[index])
                }
                try writer.write([row.id.uuidString, row.sessionID.uuidString, f.int(row.windowIndex),
                                  f.int64(row.startFrame), f.int64(row.durationFrames)]
                                 + f.timestamp(start) + f.timestamp(row.deliveredAt)
                                 + [f.list(row.topLabels), f.list(row.topScores), f.number(row.rms), f.number(row.peak),
                                    f.int(row.schemaVersion)] + scores)
            }
        }
        try verify(writer, expected: try context.fetchCount(FetchDescriptor<ClassifierWindow>(predicate: #Predicate<ClassifierWindow> { $0.deliveredAt >= lo && $0.deliveredAt < hi })))
        return writer
    }

    func exportLegacyEvents(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        let writer = try CSVFileWriter(directory: folder, fileName: "legacy_detection_events.csv", columns: [
            CSVColumn("id", "text", "Event UUID; joins detection_annotations.target_legacy_event_id.", since: 1),
            CSVColumn("session_id", "text", "Listening session (no session row exists for builds 1–2).", since: 1),
        ] + CSVColumn.timestamp("timestamp", "When the result was delivered (not audio time).", since: 1) + [
            CSVColumn("label", "text", "Top-ranked label; only respiratory-allowlisted labels were kept.", since: 1),
            CSVColumn("confidence", "number", unit: "0–1", "Classifier score. Build 1 dropped scores below 0.05.", since: 1),
            CSVColumn("window_duration", "number", unit: "seconds", "Analysis window length.", since: 1),
            CSVColumn("overlap_factor", "number", "Window overlap.", since: 1),
            CSVColumn("classifier_identifier", "text", "Classifier.", since: 1),
            CSVColumn("app_version", "text", "App version (build) that captured it.", since: 1),
            CSVColumn("is_false_positive", "boolean", "Legacy review flag; detection_annotations rows supersede it.", since: 1),
        ])
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<DetectionEvent>(predicate: #Predicate<DetectionEvent> { $0.timestamp >= lo && $0.timestamp < hi }, sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                try writer.write([row.id.uuidString, row.sessionID.uuidString] + f.timestamp(row.timestamp) + [
                    row.label, f.number(row.confidence), f.number(row.windowDuration), f.number(row.overlapFactor),
                    row.classifierIdentifier, row.appVersion, f.bool(row.isFalsePositive)])
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<DetectionEvent>(predicate: #Predicate<DetectionEvent> { $0.timestamp >= lo && $0.timestamp < hi })))
        return writer
    }

    func exportAnnotations(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        let writer = try CSVFileWriter(directory: folder, fileName: "detection_annotations.csv", columns: [
            CSVColumn("id", "text", "Annotation UUID."),
            CSVColumn("target_window_id", "text", null: "targets a legacy event", "Joins classifier_windows.id."),
            CSVColumn("target_legacy_event_id", "text", null: "targets a window", "Joins legacy_detection_events.id."),
            CSVColumn("label", "text", "Which label the verdict is about."),
            CSVColumn("verdict", "text", "falsePositive, confirmed, unsure, or cleared (withdraws earlier verdicts)."),
        ] + CSVColumn.timestamp("created_at", "When the verdict was given. The latest per target and label wins.") + [
            CSVColumn("source", "text", "Where it was given (review)."),
            CSVColumn("note", "text", null: "no note", "Free text."),
            CSVColumn("app_version", "text", "App version (build)."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ])
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<DetectionAnnotation>(predicate: #Predicate<DetectionAnnotation> { $0.createdAt >= lo && $0.createdAt < hi }, sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                try writer.write([row.id.uuidString, f.text(row.targetWindowID?.uuidString),
                                  f.text(row.targetLegacyEventID?.uuidString), row.label, row.verdict]
                                 + f.timestamp(row.createdAt)
                                 + [row.source, f.text(row.note), row.appVersion, f.int(row.schemaVersion)])
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<DetectionAnnotation>(predicate: #Predicate<DetectionAnnotation> { $0.createdAt >= lo && $0.createdAt < hi })))
        return writer
    }
}
