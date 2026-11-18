import CryptoKit
import Foundation
import SwiftData

/// What the person entered: check-ins and context events.
extension RecordExporter {
    func exportCheckIns(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        let writer = try CSVFileWriter(directory: folder, fileName: "daily_check_ins.csv", columns: [
            CSVColumn("id", "text", "Row UUID. Rows are append-only: the latest recorded_at per day_key is current."),
            CSVColumn("day_key", "text", unit: "yyyy-MM-dd", "The day described: last night (ending that morning) and that day."),
        ] + CSVColumn.timestamp("recorded_at", "When saved. Same-day vs backfilled is derivable from this and day_key.") + [
            CSVColumn("recorded_time_zone_id", "text", "Device time zone when saved."),
            CSVColumn("question_set_version", "integer", "Wording, scales and chips in force."),
            CSVColumn("daytime_symptoms", "boolean", null: "not answered", "Any breathing or allergy symptoms that day."),
            CSVColumn("daytime_severity", "integer", unit: "1 mild, 2 moderate, 3 severe", null: "not answered, or no symptoms", "Worst severity that day."),
            CSVColumn("night_waking", "boolean", null: "not answered", "Woken by cough or breathing the night ending that morning."),
            CSVColumn("rescue_inhaler_uses", "integer", unit: "uses", null: "not answered (0 means none)", "Rescue inhaler uses that day."),
            CSVColumn("activity_limited", "boolean", null: "not answered", "Symptoms limited activity."),
            CSVColumn("symptoms_presented", "list", "Chips shown; an unselected presented chip means shown and not chosen."),
            CSVColumn("symptoms_selected", "list", null: "none selected", "Chips chosen."),
            CSVColumn("windows_open", "text", null: "not answered", "Windows open at home: yes, no or partly."),
            CSVColumn("peak_flow_lpm", "integer", unit: "L/min", null: "not measured", "Peak expiratory flow from a meter."),
        ] + CSVColumn.timestamp("peak_flow_measured_at", null: "not measured", "When peak flow was entered.") + [
            CSVColumn("controller_adherence", "text", null: "not answered, or not asked (question_set_version 1)",
                      "Took controller (preventer) medication that day as prescribed: yes, partly, no or notPrescribed.",
                      since: 3),
            CSVColumn("completion_seconds", "number", unit: "seconds", null: "not recorded", "Time from opening the form to saving (data-quality signal)."),
            CSVColumn("app_version", "text", "App version (build)."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ])
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<DailyCheckIn>(predicate: #Predicate<DailyCheckIn> { $0.recordedAt >= lo && $0.recordedAt < hi }, sortBy: [SortDescriptor(\.recordedAt), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                try writer.write([row.id.uuidString, row.dayKey] + f.timestamp(row.recordedAt) + [
                    row.recordedTimeZoneID, f.int(row.questionSetVersion), f.bool(row.daytimeSymptoms),
                    f.int(row.daytimeSeverity), f.bool(row.nightWaking), f.int(row.rescueInhalerUses),
                    f.bool(row.activityLimited), f.list(row.symptomsPresented), f.list(row.symptomsSelected),
                    f.text(row.windowsOpen), f.int(row.peakFlowLPM)] + f.timestamp(row.peakFlowMeasuredAt)
                    + [f.text(row.controllerAdherence), f.number(row.completionSeconds), row.appVersion,
                       f.int(row.schemaVersion)])
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<DailyCheckIn>(predicate: #Predicate<DailyCheckIn> { $0.recordedAt >= lo && $0.recordedAt < hi })))
        return writer
    }

    func exportContextEvents(_ folder: URL, _ f: CSVFormat, _ range: DateInterval) throws -> CSVFileWriter {
        let lo = range.start, hi = range.end
        let writer = try CSVFileWriter(directory: folder, fileName: "context_events.csv", columns: [
            CSVColumn("id", "text", "Row UUID. Append-only: see supersedes_id and is_retraction."),
            CSVColumn("category", "text", "medicationStarted, medicationChanged, medicationStopped, illness, travel, movedHome or other."),
            CSVColumn("note", "text", null: "no note", "Free text (e.g. medication and dose)."),
            CSVColumn("start_day_key", "text", unit: "yyyy-MM-dd", "First local day affected."),
            CSVColumn("end_day_key", "text", unit: "yyyy-MM-dd", null: "single day or ongoing", "Last local day affected."),
        ] + CSVColumn.timestamp("recorded_at", "When entered.") + [
            CSVColumn("recorded_time_zone_id", "text", "Device time zone when entered."),
            CSVColumn("supersedes_id", "text", null: "an original entry", "The row this edits or retracts; the latest row in a chain is current."),
            CSVColumn("is_retraction", "boolean", "true if this row removes the event it supersedes."),
            CSVColumn("app_version", "text", "App version (build)."),
            CSVColumn("schema_version", "integer", "Schema version that wrote the row."),
        ])
        var seen: Set<UUID> = []
        try forEachBatch(FetchDescriptor<ContextEvent>(predicate: #Predicate<ContextEvent> { $0.recordedAt >= lo && $0.recordedAt < hi }, sortBy: [SortDescriptor(\.recordedAt), SortDescriptor(\.id)])) { rows in
            for row in rows {
                guard seen.insert(row.id).inserted else { throw ExportError.duplicateRow(table: writer.fileName) }
                try writer.write([row.id.uuidString, row.category, row.note, row.startDayKey, f.text(row.endDayKey)]
                                 + f.timestamp(row.recordedAt) + [row.recordedTimeZoneID,
                                    f.text(row.supersedesID?.uuidString), f.bool(row.isRetraction), row.appVersion,
                                    f.int(row.schemaVersion)])
            }
        }
        try verify(writer, expected: try ModelContext(modelContainer).fetchCount(FetchDescriptor<ContextEvent>(predicate: #Predicate<ContextEvent> { $0.recordedAt >= lo && $0.recordedAt < hi })))
        return writer
    }

    // MARK: Helpers
}
