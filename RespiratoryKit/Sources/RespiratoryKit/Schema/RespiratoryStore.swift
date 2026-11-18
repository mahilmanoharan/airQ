import Foundation
import SwiftData

public typealias ListeningSession = SchemaV2.ListeningSession
public typealias ClassifierWindow = SchemaV2.ClassifierWindow
public typealias DetectionAnnotation = SchemaV2.DetectionAnnotation
public typealias DailyRecord = SchemaV2.DailyRecord
public typealias EnvironmentalObservation = SchemaV2.EnvironmentalObservation
public typealias HourlyAirQuality = SchemaV2.HourlyAirQuality
public typealias DailyCheckIn = SchemaV3.DailyCheckIn
public typealias ContextEvent = SchemaV2.ContextEvent

public enum RespiratoryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
        ]
    }
}

/// The single versioned container shared by every store actor.
public enum RespiratoryStore {
    /// Written into each new row's `schemaVersion`.
    public static let schemaVersion = 3

    public static var schema: Schema { Schema(versionedSchema: SchemaV3.self) }

    /// Opens the default on-disk store (the same file builds 1–2 used), migrating it if needed.
    /// Never deletes or replaces an existing store: a failure here must surface, not be worked around.
    @concurrent
    public static func openContainer() async throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema)
        purgeStoreFilesIfErasePending(configuration)
        return try makeContainer(configuration: configuration)
    }

    // MARK: Erasing (user-initiated only)

    /// UserDefaults flag set by `eraseAll`: the rows are gone, and the database *file* (which can
    /// still hold the deleted bytes in free pages) should be removed at the next launch.
    static let erasePendingKey = "airQErasePending"

    /// Deletes every row of every model and marks the store file for removal at the next launch.
    /// This is the one place the record is ever deleted, and only ever because the person asked in
    /// the app (see `EraseDataView`); nothing else may call it. The rows are deleted first, so if
    /// anything fails the store simply keeps the rows it still has and the error surfaces.
    @concurrent
    public static func eraseAll(in container: ModelContainer, defaultsSuite: String? = nil) async throws {
        let defaults = defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        let context = ModelContext(container)
        // Remember when metered requests were made (times only) so erasing can't reset the free-tier
        // usage count that guards Google requests.
        let remembered = try recentRequestTimes(in: context)
        for model in SchemaV3.models { try wipe(model, in: context) }
        try context.save()
        // After the rows are really gone: if the delete had failed, adding these would count the same
        // requests twice (once here, once in the surviving rows).
        RequestLedger.add(remembered, to: defaults)
        defaults.set(true, forKey: erasePendingKey)
    }

    private static func recentRequestTimes(in context: ModelContext) throws -> [String: [Date]] {
        let counted = EnvironmentalAttemptRecord.Status.allCases.filter(\.mayHaveReachedProvider).map(\.rawValue)
        let since = Date().addingTimeInterval(-RequestLedger.retention)
        var recentRequests = FetchDescriptor<SchemaV2.EnvironmentalObservation>(predicate: #Predicate {
            $0.requestedAt >= since && counted.contains($0.status)
        })
        // Only the provider and time matter here; don't materialise raw bodies and parsed values.
        recentRequests.propertiesToFetch = [\.provider, \.requestedAt]
        let recent = try context.fetch(recentRequests)
        return Dictionary(grouping: recent, by: \.provider).mapValues { $0.map(\.requestedAt) }
    }

    private static func wipe<T: PersistentModel>(_ model: T.Type, in context: ModelContext) throws {
        try context.delete(model: model)
    }

    /// Tables only a person's own actions fill. Provider attempts, days and history are
    /// re-created by simply using the app, so they don't count as data worth protecting.
    private static func userAuthoredRowCount(in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<SchemaV2.ListeningSession>())
            + context.fetchCount(FetchDescriptor<SchemaV2.ClassifierWindow>())
            + context.fetchCount(FetchDescriptor<SchemaV1.DetectionEvent>())
            + context.fetchCount(FetchDescriptor<SchemaV2.DetectionAnnotation>())
            + context.fetchCount(FetchDescriptor<SchemaV3.DailyCheckIn>())
            + context.fetchCount(FetchDescriptor<SchemaV2.ContextEvent>())
    }

    /// After an erase, removes the store's files so nothing deleted lingers on disk, but only when
    /// the person hasn't recorded anything new since (new check-ins, labels, context events or
    /// listening). Otherwise the emptied store stays: a purge would destroy their newer data.
    /// Never runs unless the erase flag is set, and never throws: a failure leaves the store as is.
    static func purgeStoreFilesIfErasePending(_ configuration: ModelConfiguration, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: erasePendingKey) else { return }
        // The container is scoped to this check so its files are closed before any are removed.
        let remembered: [String: [Date]]
        do {
            let container = try makeContainer(configuration: configuration)
            guard try userAuthoredRowCount(in: container) == 0 else {
                // Newer user records must survive. Spend the flag so a later launch won't purge them.
                defaults.removeObject(forKey: erasePendingKey)
                return
            }
            remembered = try recentRequestTimes(in: ModelContext(container))
        } catch {
            return  // Can't verify that this purge is safe. Keep the flag for a later attempt.
        }
        removeStoreFiles(at: configuration.url)
        // Only a completed purge clears the flag; a failed removal is retried at the next launch.
        if !FileManager.default.fileExists(atPath: configuration.url.path(percentEncoded: false)) {
            RequestLedger.add(remembered, to: defaults)
            defaults.removeObject(forKey: erasePendingKey)
        }
    }

    static func removeStoreFiles(at url: URL) {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let support = directory.appending(path: ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory)
        for file in [url] + ["-wal", "-shm"].map({ directory.appending(path: url.lastPathComponent + $0) }) + [support] {
            try? manager.removeItem(at: file)
        }
    }

    public static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: RespiratoryMigrationPlan.self, configurations: configuration)
    }

    /// Bytes on disk for the store at `url`: the SQLite file, its -wal/-shm sidecars and the hidden
    /// `.<name>_SUPPORT` folder where SwiftData keeps external-storage blobs (raw provider bodies).
    /// Missing parts count as zero; nil only when `url` isn't a file URL.
    public static func diskUsage(ofStoreAt url: URL) -> Int64? {
        guard url.isFileURL else { return nil }
        let manager = FileManager.default
        func size(_ file: URL) -> Int64 {
            (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize).map(Int64.init) ?? 0
        }
        // Sidecars are siblings named "<store>-wal"/"-shm" (built from the name, never from a
        // percent-encoded path: the real store lives under "Application Support").
        let directory = url.deletingLastPathComponent()
        let sidecars = ["-wal", "-shm"].map { directory.appending(path: url.lastPathComponent + $0) }
        var total = ([url] + sidecars).reduce(0) { $0 + size($1) }
        let support = url.deletingLastPathComponent()
            .appending(path: ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory)
        if let files = manager.enumerator(at: support, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            for case let file as URL in files { total += size(file) }
        }
        return total
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
}
