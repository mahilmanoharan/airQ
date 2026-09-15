import Foundation
import SwiftData

/// A `Sendable` snapshot of a stored `DetectionEvent`. `@Model` classes are
/// marked `Sendable` by macro expansion, but a live instance is still tied
/// to the `ModelActor` that fetched it — passing it directly to another
/// isolation domain compiles but isn't actually safe. This plain value type
/// is what crosses actor boundaries instead; `DetectionAnalysis`'s pure
/// functions only ever see this, never a live `DetectionEvent`.
///
/// Deliberately keyed by `DetectionEvent.id` (a plain `UUID` we control),
/// not SwiftData's `PersistentIdentifier` — that type has no public
/// initializer, which would make `DetectionAnalysis`'s pure functions
/// untestable with plain fixture data.
public struct DetectionSnapshot: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let label: String
    public let confidence: Double
    public let isFalsePositive: Bool

    public init(
        id: UUID,
        timestamp: Date,
        label: String,
        confidence: Double,
        isFalsePositive: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.confidence = confidence
        self.isFalsePositive = isFalsePositive
    }
}

/// Background-safe SwiftData access for detection events. All writes and
/// reads happen on this actor's own isolated `ModelContext`, so audio
/// classification results arriving from `AudioAnalysisController`'s
/// dedicated queue never touch the main actor to get persisted.
@ModelActor
public actor DetectionStore: DetectionStoring {
    /// Package async functions use the generic executor (no default MainActor isolation).
    /// Construct the ModelActor here so its ModelContext is not bound to the UI executor.
    public static func open() async throws -> DetectionStore {
        let container = try ModelContainer(for: DetectionEvent.self)
        return DetectionStore(modelContainer: container)
    }

    public func record(
        sessionID: UUID,
        label: String,
        confidence: Double,
        timestamp: Date,
        config: DetectionConfig
    ) throws {
        let event = DetectionEvent(
            sessionID: sessionID,
            timestamp: timestamp,
            label: label,
            confidence: confidence,
            config: config
        )
        modelContext.insert(event)
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }

    public func setFalsePositive(_ id: UUID, isFalsePositive: Bool) throws {
        var descriptor = FetchDescriptor<DetectionEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let event = try modelContext.fetch(descriptor).first else { return }
        event.isFalsePositive = isFalsePositive
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }

    public func fetchAllSnapshots() throws -> [DetectionSnapshot] {
        try fetchSnapshots(limit: nil, newestFirst: false)
    }

    public func fetchSnapshots(limit: Int?, newestFirst: Bool) throws -> [DetectionSnapshot] {
        var descriptor = FetchDescriptor<DetectionEvent>(sortBy: [
            SortDescriptor(\.timestamp, order: newestFirst ? .reverse : .forward)
        ])
        if let limit { descriptor.fetchLimit = max(1, limit) }
        let events = try modelContext.fetch(descriptor)
        return events.map {
            DetectionSnapshot(
                id: $0.id,
                timestamp: $0.timestamp,
                label: $0.label,
                confidence: $0.confidence,
                isFalsePositive: $0.isFalsePositive
            )
        }
    }
}
