import Foundation
import SwiftData

/// Events that break comparability across the record. Stored as raw values, so an unknown future
/// category is kept verbatim instead of failing to decode.
public enum ContextEventCategory: String, Sendable, CaseIterable, Identifiable {
    case medicationStarted, medicationChanged, medicationStopped, illness, travel, movedHome, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .medicationStarted: "Started medication"
        case .medicationChanged: "Changed medication"
        case .medicationStopped: "Stopped medication"
        case .illness: "Illness"
        case .travel: "Travel"
        case .movedHome: "Moved home"
        case .other: "Other"
        }
    }

    /// Whether a missing end date means "still ongoing" (illness, travel) rather than a single day.
    public var isOpenEndedWithoutEndDate: Bool {
        switch self {
        case .illness, .travel: true
        default: false
        }
    }
}

/// What the user entered. Day keys are local "yyyy-MM-dd"; `endDayKey == nil` means a single day or
/// still ongoing, depending on the category.
public struct ContextEventDraft: Sendable, Equatable {
    public var category: String
    public var note: String
    public var startDayKey: String
    public var endDayKey: String?

    public init(category: String, note: String, startDayKey: String, endDayKey: String?) {
        self.category = category
        self.note = note
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
    }
}

/// One stored row, exactly as written (append-only: edits and retractions are further rows).
public struct ContextEventRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let draft: ContextEventDraft
    public let recordedAt: Date
    public let recordedTimeZoneID: String
    public let supersedesID: UUID?
    public let isRetraction: Bool

    public init(id: UUID, draft: ContextEventDraft, recordedAt: Date, recordedTimeZoneID: String,
                supersedesID: UUID?, isRetraction: Bool) {
        self.id = id
        self.draft = draft
        self.recordedAt = recordedAt
        self.recordedTimeZoneID = recordedTimeZoneID
        self.supersedesID = supersedesID
        self.isRetraction = isRetraction
    }
}

/// The current state of one event chain, resolved at read time.
public struct ContextEventSnapshot: Sendable, Equatable, Identifiable {
    /// The latest row in the chain; revise or retract by this id.
    public let id: UUID
    /// The first row: a stable identity across edits.
    public let originalID: UUID
    public let draft: ContextEventDraft
    public let firstRecordedAt: Date
    public let lastRecordedAt: Date
    public let revisionCount: Int
    public let isRetracted: Bool
}

public enum ContextEventError: LocalizedError, Sendable, Equatable {
    case endBeforeStart, invalidDay(String), unknownEvent, alreadyRetracted

    public var errorDescription: String? {
        switch self {
        case .endBeforeStart: "The end date is before the start date."
        case .invalidDay(let key): "\(key) is not a valid date."
        case .unknownEvent: "That event no longer exists."
        case .alreadyRetracted: "That event was already removed."
        }
    }
}

public enum ContextEventResolution {
    /// Groups rows into chains by following `supersedesID` to the root, then takes each chain's
    /// latest row (by `recordedAt`, ties broken by id). A chain whose latest row is a retraction is
    /// retracted. Nothing is ever deleted, so every earlier version stays in the export.
    public static func resolve(_ rows: [ContextEventRow]) -> [ContextEventSnapshot] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func root(of row: ContextEventRow) -> UUID {
            var current = row
            var seen: Set<UUID> = [row.id]
            while let parent = current.supersedesID, let next = byID[parent], seen.insert(parent).inserted {
                current = next
            }
            return current.id
        }
        let chains = Dictionary(grouping: rows, by: root(of:))
        return chains.compactMap { rootID, chain -> ContextEventSnapshot? in
            let ordered = chain.sorted { ($0.recordedAt, $0.id.uuidString) < ($1.recordedAt, $1.id.uuidString) }
            guard let first = ordered.first, let latest = ordered.last else { return nil }
            // A retraction row carries no new content, so show the last real version.
            let content = ordered.last(where: { !$0.isRetraction }) ?? first
            return ContextEventSnapshot(id: latest.id, originalID: rootID, draft: content.draft,
                                        firstRecordedAt: first.recordedAt, lastRecordedAt: latest.recordedAt,
                                        revisionCount: ordered.count(where: { !$0.isRetraction }) - 1,
                                        isRetracted: latest.isRetraction)
        }
        .sorted { ($0.draft.startDayKey, $0.firstRecordedAt) > ($1.draft.startDayKey, $1.firstRecordedAt) }
    }
}

public protocol ContextEventStoring: Sendable {
    func contextEventRows() async throws -> [ContextEventRow]
    /// Appends a row. `supersedes` makes it an edit of that row; `isRetraction` a removal.
    func appendContextEvent(_ draft: ContextEventDraft, supersedes: UUID?, isRetraction: Bool,
                            recordedAt: Date, timeZone: TimeZone, appVersion: String) async throws
}

extension RecordStore: ContextEventStoring {
    public func contextEventRows() throws -> [ContextEventRow] {
        try modelContext.fetch(FetchDescriptor<ContextEvent>(sortBy: [SortDescriptor(\.recordedAt)])).map {
            ContextEventRow(id: $0.id,
                            draft: ContextEventDraft(category: $0.category, note: $0.note,
                                                     startDayKey: $0.startDayKey, endDayKey: $0.endDayKey),
                            recordedAt: $0.recordedAt, recordedTimeZoneID: $0.recordedTimeZoneID,
                            supersedesID: $0.supersedesID, isRetraction: $0.isRetraction)
        }
    }

    public func appendContextEvent(_ draft: ContextEventDraft, supersedes: UUID?, isRetraction: Bool,
                                   recordedAt: Date, timeZone: TimeZone, appVersion: String) throws {
        try requireWritesAvailable()
        for key in [draft.startDayKey, draft.endDayKey].compactMap(\.self) where LocalDay(key: key, in: timeZone) == nil {
            throw ContextEventError.invalidDay(key)
        }
        if let end = draft.endDayKey, end < draft.startDayKey { throw ContextEventError.endBeforeStart }
        if let supersedes {
            let target = FetchDescriptor<ContextEvent>(predicate: #Predicate { $0.id == supersedes })
            guard try modelContext.fetchCount(target) == 1 else { throw ContextEventError.unknownEvent }
            let chain = ContextEventResolution.resolve(try contextEventRows())
            guard let current = chain.first(where: { $0.id == supersedes }) else {
                throw ContextEventError.unknownEvent  // Only the latest version may be revised.
            }
            if current.isRetracted { throw ContextEventError.alreadyRetracted }
        }
        modelContext.insert(ContextEvent(
            category: draft.category, note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            startDayKey: draft.startDayKey, endDayKey: draft.endDayKey, recordedAt: recordedAt,
            recordedTimeZoneID: timeZone.identifier, supersedesID: supersedes, isRetraction: isRetraction,
            appVersion: appVersion))
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }
}
