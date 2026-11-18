import Foundation
import SwiftData

/// Shared by the per-table writers in `RecordExporter+Detections/Environment/Entries.swift`.
extension RecordExporter {
    /// Walks the matching rows in sort order, a page at a time through short-lived contexts so fetched
    /// objects are released per page. The ordered identifiers are read once, so paging cost is linear
    /// in the table (offset paging rescanned every earlier row) and rows written mid-export cannot
    /// shift a page; the count check in `verify` still catches a row that vanished.
    func forEachBatch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, _ body: ([T]) throws -> Void) throws {
        try Task.checkCancellation()
        var ordered = descriptor
        ordered.includePendingChanges = false // a sorted identifier fetch can't merge unsaved changes
        let ids = try ModelContext(modelContainer).fetchIdentifiers(ordered)
        var start = 0
        while start < ids.count {
            try Task.checkCancellation()
            let context = ModelContext(modelContainer)
            let page = ids[start..<min(start + Self.batchSize, ids.count)]
            try body(page.compactMap { context.model(for: $0) as? T })
            start += Self.batchSize
        }
        try Task.checkCancellation()
    }

    /// Duplicates throw during writing and this catches skipped rows, so an export is complete or it fails.
    func verify(_ writer: CSVFileWriter, expected: Int) throws {
        guard writer.rowCount == expected else {
            throw ExportError.incomplete(table: writer.fileName, expected: expected, exported: writer.rowCount)
        }
    }
}
