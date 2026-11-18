import Foundation
import SwiftData
import Testing
@testable import RespiratoryKit

@Suite("Erase all data")
struct EraseTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private let at = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Fixture {
        let directory: URL
        let configuration: ModelConfiguration
        let container: ModelContainer
        let defaults: UserDefaults
        let suite: String
        var storeURL: URL { configuration.url }
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: "airq-erase-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: RespiratoryStore.schema, url: directory.appending(path: "test.store"))
        let suite = "airq.erase.\(UUID().uuidString)"
        return Fixture(directory: directory, configuration: configuration,
                       container: try RespiratoryStore.makeContainer(configuration: configuration),
                       defaults: try #require(UserDefaults(suiteName: suite)), suite: suite)
    }

    private func populate(_ container: ModelContainer, largeBody: Bool = false) async throws {
        let records = RecordStore(modelContainer: container)
        let detections = DetectionStore(modelContainer: container)
        var waqi = EnvironmentalAttemptRecord(provider: "waqi", requestKind: "current", requestedAt: at,
                                              timeZoneID: zone.identifier, status: .success, parserVersion: 1, appVersion: "t")
        waqi.aqi = 42
        // Large bodies are stored outside the SQLite file, in the hidden _SUPPORT folder.
        waqi.rawResponse = largeBody ? Data(repeating: 7, count: 2_000_000) : Data("{}".utf8)
        try await records.record(waqi)
        try await records.ensureDay(containing: at, in: zone, appVersion: "t")
        try await records.appendContextEvent(ContextEventDraft(category: "other", note: "n", startDayKey: "2026-09-20", endDayKey: nil),
                                             supersedes: nil, isRetraction: false, recordedAt: at, timeZone: zone, appVersion: "t")
        try await records.appendCheckIn(CheckInDraft(dayKey: "2026-09-21", daytimeSymptoms: false),
                                        recordedAt: at, timeZone: zone, completionSeconds: 3, appVersion: "t")
        try await detections.recordLegacy(sessionID: UUID(), label: "cough", confidence: 0.5, timestamp: at,
                                          config: DetectionConfig(windowDuration: 1, overlapFactor: 0.5,
                                                                  classifierIdentifier: "version1", appVersion: "1"))
    }

    private func totalRows(_ container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<SchemaV1.DetectionEvent>())
            + context.fetchCount(FetchDescriptor<SchemaV2.ListeningSession>())
            + context.fetchCount(FetchDescriptor<SchemaV2.ClassifierWindow>())
            + context.fetchCount(FetchDescriptor<SchemaV2.DetectionAnnotation>())
            + context.fetchCount(FetchDescriptor<SchemaV2.DailyRecord>())
            + context.fetchCount(FetchDescriptor<SchemaV2.EnvironmentalObservation>())
            + context.fetchCount(FetchDescriptor<SchemaV2.HourlyAirQuality>())
            + context.fetchCount(FetchDescriptor<SchemaV3.DailyCheckIn>())
            + context.fetchCount(FetchDescriptor<SchemaV2.ContextEvent>())
    }

    private func cleanUp(_ fixture: Fixture) {
        fixture.defaults.removePersistentDomain(forName: fixture.suite)
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    @Test("Erasing deletes every row of every table, flags the file purge, and the store keeps working")
    func erasesEveryTable() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try await populate(fixture.container)
        #expect(try totalRows(fixture.container) >= 5)

        try await RespiratoryStore.eraseAll(in: fixture.container, defaultsSuite: fixture.suite)
        #expect(try totalRows(fixture.container) == 0)
        #expect(fixture.defaults.bool(forKey: RespiratoryStore.erasePendingKey))

        try await populate(fixture.container)  // still usable afterwards
        #expect(try totalRows(fixture.container) >= 5)
    }

    @Test("The next launch removes the database files, including external blobs, and clears the flag")
    func purgesFilesWhenNothingNewWasRecorded() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try await populate(fixture.container, largeBody: true)
        let support = fixture.directory.appending(path: ".test_SUPPORT", directoryHint: .isDirectory)
        #expect(FileManager.default.fileExists(atPath: support.path(percentEncoded: false)), "the blob is external")
        try await RespiratoryStore.eraseAll(in: fixture.container, defaultsSuite: fixture.suite)
        // Stands in for the relaunch: the purge opens the store itself, checks it, then removes its files.
        let config = fixture.configuration
        let defaults = fixture.defaults
        RespiratoryStore.purgeStoreFilesIfErasePending(config, defaults: defaults)

        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: support.path(percentEncoded: false)))
        #expect(!defaults.bool(forKey: RespiratoryStore.erasePendingKey))
        // And a fresh store opens cleanly in its place.
        let reopened = try RespiratoryStore.makeContainer(configuration: config)
        #expect(try totalRows(reopened) == 0)
    }

    @Test("Anything the person recorded after erasing is kept: the flag clears but the file stays")
    func keepsNewerUserData() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try await populate(fixture.container)
        try await RespiratoryStore.eraseAll(in: fixture.container, defaultsSuite: fixture.suite)
        let records = RecordStore(modelContainer: fixture.container)
        try await records.appendCheckIn(CheckInDraft(dayKey: "2026-09-25", daytimeSymptoms: true, daytimeSeverity: 1),
                                        recordedAt: at, timeZone: zone, completionSeconds: 3, appVersion: "t")

        RespiratoryStore.purgeStoreFilesIfErasePending(fixture.configuration, defaults: fixture.defaults)
        #expect(FileManager.default.fileExists(atPath: fixture.storeURL.path(percentEncoded: false)))
        #expect(!fixture.defaults.bool(forKey: RespiratoryStore.erasePendingKey))
        let context = ModelContext(fixture.container)
        #expect(try context.fetchCount(FetchDescriptor<SchemaV3.DailyCheckIn>()) == 1)
    }

    @Test("Purging after erase carries forward the usage from later provider fetches")
    func purgeKeepsLaterRequestUsage() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try await RespiratoryStore.eraseAll(in: fixture.container, defaultsSuite: fixture.suite)
        let records = RecordStore(modelContainer: fixture.container)
        let now = Date()
        let attempt = EnvironmentalAttemptRecord(provider: "googlePollen", requestKind: "forecast", requestedAt: now,
            timeZoneID: zone.identifier, status: .success, parserVersion: 1, appVersion: "t")
        try await records.record(attempt)

        RespiratoryStore.purgeStoreFilesIfErasePending(fixture.configuration, defaults: fixture.defaults)

        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path(percentEncoded: false)))
        #expect(RequestLedger.count(provider: "googlePollen", since: now.addingTimeInterval(-60), in: fixture.defaults) == 1)
    }

    @Test("Without an erase, launching never touches the store")
    func noFlagNoPurge() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try await populate(fixture.container)
        RespiratoryStore.purgeStoreFilesIfErasePending(fixture.configuration, defaults: fixture.defaults)
        #expect(FileManager.default.fileExists(atPath: fixture.storeURL.path(percentEncoded: false)))
        #expect(try totalRows(fixture.container) >= 5)
    }
}

@Suite("Request ledger")
struct RequestLedgerTests {
    private func suite() throws -> (UserDefaults, String) {
        let name = "airq.ledger.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("Counts and latest by provider, dropping entries past the retention")
    func countsAndPrunes() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = now.addingTimeInterval(-40 * 86_400)
        let recent = [now.addingTimeInterval(-3_600), now.addingTimeInterval(-7_200)]
        RequestLedger.add(["googlePollen": recent + [old], "googleAirQuality": [recent[0]]], to: defaults, now: now)
        #expect(RequestLedger.count(provider: "googlePollen", since: now.addingTimeInterval(-31 * 86_400), in: defaults) == 2)
        #expect(RequestLedger.count(provider: "googlePollen", since: now.addingTimeInterval(-1_800), in: defaults) == 0)
        #expect(RequestLedger.latest(provider: "googlePollen", in: defaults) == recent[0])
        #expect(RequestLedger.latest(provider: "waqi", in: defaults) == nil)
    }

    @Test("Erasing keeps the times of metered requests so the free-tier count can't be reset")
    func eraseKeepsUsage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "airq-ledger-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: RespiratoryStore.schema, url: directory.appending(path: "t.store"))
        let container = try RespiratoryStore.makeContainer(configuration: configuration)
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let records = RecordStore(modelContainer: container)
        let requestedAt = Date().addingTimeInterval(-3_600)
        for provider in ["googlePollen", "googlePollen", "googleAirQuality"] {
            try await records.record(EnvironmentalAttemptRecord(provider: provider, requestKind: "x", requestedAt: requestedAt,
                                                                timeZoneID: "UTC", status: .success, parserVersion: 1, appVersion: "t"))
        }
        // A request that never left the phone is not usage and must not be remembered.
        try await records.record(EnvironmentalAttemptRecord(provider: "googlePollen", requestKind: "x", requestedAt: requestedAt,
                                                            timeZoneID: "UTC", status: .notSent, parserVersion: 1, appVersion: "t"))
        try await RespiratoryStore.eraseAll(in: container, defaultsSuite: name)
        let since = Date().addingTimeInterval(-31 * 86_400)
        #expect(RequestLedger.count(provider: "googlePollen", since: since, in: defaults) == 2)
        #expect(RequestLedger.count(provider: "googleAirQuality", since: since, in: defaults) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SchemaV2.EnvironmentalObservation>()) == 0)
    }
}
