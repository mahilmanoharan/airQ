import CryptoKit
import Foundation

/// One exported column and its data-dictionary entry. The dictionary is generated from the same
/// specs that write the files, so every column is documented by construction.
struct CSVColumn: Sendable {
    let name: String
    let type: String
    let unit: String
    /// What an empty cell means for this column.
    let nullMeaning: String
    let description: String
    let sinceSchema: Int

    init(_ name: String, _ type: String, unit: String = "", null nullMeaning: String = "never empty",
         _ description: String, since sinceSchema: Int = 2) {
        self.name = name
        self.type = type
        self.unit = unit
        self.nullMeaning = nullMeaning
        self.description = description
        self.sinceSchema = sinceSchema
    }

    /// A timestamp is exported twice: ISO 8601 with offset, and Unix epoch seconds.
    static func timestamp(_ name: String, null: String = "never empty", _ description: String,
                          since: Int = 2) -> [CSVColumn] {
        [CSVColumn(name, "timestamp", unit: "ISO 8601, export time zone offset", null: null, description, since: since),
         CSVColumn("\(name)_epoch", "number", unit: "seconds since 1970-01-01 UTC", null: null,
                   "\(name) as Unix time.", since: since)]
    }
}

/// Streams RFC 4180 CSV (CRLF line endings, quoted where needed) to disk, hashing as it writes.
final class CSVFileWriter {
    let fileName: String
    let columns: [CSVColumn]
    private let handle: FileHandle
    private var hasher = SHA256()
    private var buffer = Data()
    private(set) var rowCount = 0
    private static let leadingWhitespace = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)

    init(directory: URL, fileName: String, columns: [CSVColumn]) throws {
        try Task.checkCancellation()
        self.fileName = fileName
        self.columns = columns
        let url = directory.appending(path: fileName)
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
        }
        handle = try FileHandle(forWritingTo: url)
        append(columns.map(\.name))
    }

    func write(_ fields: [String]) throws {
        try Task.checkCancellation()
        precondition(fields.count == columns.count, "\(fileName): \(fields.count) fields for \(columns.count) columns")
        append(zip(fields, columns).map { field, column in
            column.type == "text" || column.type == "list" ? Self.protectText(field) : field
        })
        rowCount += 1
        if buffer.count > 256 * 1024 { try flush() }
    }

    /// Flushes, closes, and returns the SHA-256 of the file's bytes as lowercase hex.
    func finish() throws -> String {
        try flush()
        try handle.close()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func append(_ fields: [String]) {
        buffer.append(contentsOf: Data((fields.map(Self.escape).joined(separator: ",") + "\r\n").utf8))
    }

    private func flush() throws {
        try Task.checkCancellation()
        guard !buffer.isEmpty else { return }
        hasher.update(data: buffer)
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    static func escape(_ field: String) -> String {
        // CRLF is a single Swift Character, so look for individual Unicode scalars.
        guard field.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func protectText(_ field: String) -> String {
        switch field.unicodeScalars.first {
        case "'", "\t", "\r", "\n": return "'" + field
        default: break
        }
        let firstContent = field.unicodeScalars.drop(while: leadingWhitespace.contains).first
        switch firstContent {
        case "=", "+", "-", "@", "＝", "＋", "－", "＠": return "'" + field
        default: return field
        }
    }
}

/// Cell formatting shared by every table. Empty string is null.
struct CSVFormat: Sendable {
    let timeZone: TimeZone
    private let iso: Date.ISO8601FormatStyle

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
        iso = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: true).timeSeparator(.colon).timeZone(separator: .colon)
    }

    func timestamp(_ date: Date?) -> [String] {
        guard let date else { return ["", ""] }
        return [date.formatted(iso), String(format: "%.3f", date.timeIntervalSince1970)]
    }

    func text(_ value: String?) -> String { value ?? "" }
    func int(_ value: Int?) -> String { value.map(String.init) ?? "" }
    func int64(_ value: Int64?) -> String { value.map(String.init) ?? "" }
    func bool(_ value: Bool?) -> String { value.map { $0 ? "true" : "false" } ?? "" }

    func number(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.isNaN { return "NaN" }
        return String(value)
    }

    func number(_ value: Float?) -> String { number(value.map(Double.init)) }

    /// Lists are pipe-joined; labels and codes never contain a pipe.
    func list(_ values: [String]) -> String { values.joined(separator: "|") }
    func list(_ values: [Float]) -> String { values.map { number($0) }.joined(separator: "|") }
}
