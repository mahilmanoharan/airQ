import Foundation
import SwiftData
import Testing
@testable import RespiratoryKit

/// Exact copy of the unversioned model shipped in builds 1–2 (entity name "DetectionEvent"),
/// used only to create a store the way those builds did.
enum UnversionedBuild2 {
    @Model
    final class DetectionEvent {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var timestamp: Date = Date()
        var label: String = ""
        var confidence: Double = 0
        var windowDuration: TimeInterval = 0
        var overlapFactor: Double = 0
        var classifierIdentifier: String = ""
        var appVersion: String = ""
        var isFalsePositive: Bool = false

        init(id: UUID, sessionID: UUID, timestamp: Date, label: String, confidence: Double, isFalsePositive: Bool) {
            self.id = id
            self.sessionID = sessionID
            self.timestamp = timestamp
            self.label = label
            self.confidence = confidence
            self.windowDuration = 0.975
            self.overlapFactor = 0.5
            self.classifierIdentifier = "version1"
            self.appVersion = "1.0 (2)"
            self.isFalsePositive = isFalsePositive
        }
    }
}

@Suite("Schema migration")
struct SchemaMigrationTests {
    private func temporaryStoreURL() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "default.store")
    }

    @Test("A store written by builds 1–2 opens as V1 and migrates to V2 with legacy rows untouched")
    func legacyStoreMigrates() throws {
        let url = try temporaryStoreURL()
        let id = UUID(), sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        do {
            let legacy = try ModelContainer(for: UnversionedBuild2.DetectionEvent.self,
                                            configurations: ModelConfiguration(url: url))
            let context = ModelContext(legacy)
            context.insert(UnversionedBuild2.DetectionEvent(id: id, sessionID: sessionID, timestamp: timestamp,
                                                            label: "cough", confidence: 0.42, isFalsePositive: true))
            try context.save()
        }

        let container = try RespiratoryStore.makeContainer(
            configuration: ModelConfiguration(schema: RespiratoryStore.schema, url: url))
        let rows = try ModelContext(container).fetch(FetchDescriptor<DetectionEvent>())

        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.id == id)
        #expect(row.sessionID == sessionID)
        #expect(row.timestamp == timestamp)
        #expect(row.label == "cough")
        #expect(row.confidence == 0.42)
        #expect(row.windowDuration == 0.975)
        #expect(row.overlapFactor == 0.5)
        #expect(row.classifierIdentifier == "version1")
        #expect(row.appVersion == "1.0 (2)")
        #expect(row.isFalsePositive)
    }

    /// Fixture values shared by the V2 fixture writer and the migration test.
    enum V2Fixture {
        static let checkInID = UUID(uuidString: "6A1F0C3E-8B7D-4E2A-9C51-0D3B7E4F2A10")!  // Literal UUID.
        static let eventID = UUID(uuidString: "B2E4D6F8-1A3C-4E5F-8A7B-9C0D1E2F3A4B")!  // Literal UUID.
        static let recordedAt = Date(timeIntervalSince1970: 1_790_000_000)
    }

    /// Regenerates `Fixtures/SchemaV2Store` (a store written by the frozen V2 schema). It must run
    /// alone: SwiftData caches one class per entity name per process, so writing V2 objects while
    /// V3 objects are in use corrupts the encoding. Run with
    /// `WRITE_V2_FIXTURE=<dir> swift test --filter writeV2Fixture`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WRITE_V2_FIXTURE"] != nil))
    func writeV2Fixture() throws {
        let directory = URL(filePath: try #require(ProcessInfo.processInfo.environment["WRITE_V2_FIXTURE"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: SchemaV2.self)
        let v2 = try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, url: directory.appending(path: "default.store")))
        let context = ModelContext(v2)
        let row = SchemaV2.DailyCheckIn(id: V2Fixture.checkInID, dayKey: "2026-09-21", recordedAt: V2Fixture.recordedAt,
                                        recordedTimeZoneID: "America/Los_Angeles", questionSetVersion: 1,
                                        symptomsPresented: ["cough", "wheeze"], appVersion: "1.0 (3)", schemaVersion: 2)
        row.daytimeSymptoms = true
        row.daytimeSeverity = 2
        row.rescueInhalerUses = 3
        row.symptomsSelected = ["cough"]
        row.peakFlowLPM = 420
        context.insert(row)
        context.insert(SchemaV2.ContextEvent(id: V2Fixture.eventID, category: "illness", note: "cold",
                                             startDayKey: "2026-09-20", endDayKey: nil, recordedAt: V2Fixture.recordedAt,
                                             recordedTimeZoneID: "UTC", appVersion: "1.0 (3)", schemaVersion: 2))
        try context.save()
    }

    @Test("A store written by V2 migrates to V3: check-ins keep every answer, adherence reads nil, other models are untouched")
    func v2StoreMigratesToV3() throws {
        let fixture = try #require(Bundle.module.url(forResource: "SchemaV2Store", withExtension: nil))
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: fixture, to: directory)
        let url = directory.appending(path: "default.store")

        let container = try RespiratoryStore.makeContainer(
            configuration: ModelConfiguration(schema: RespiratoryStore.schema, url: url))
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<DailyCheckIn>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.id == V2Fixture.checkInID && row.dayKey == "2026-09-21" && row.recordedAt == V2Fixture.recordedAt)
        #expect(row.questionSetVersion == 1 && row.schemaVersion == 2 && row.appVersion == "1.0 (3)")
        #expect(row.daytimeSymptoms == true && row.daytimeSeverity == 2 && row.rescueInhalerUses == 3)
        #expect(row.symptomsPresented == ["cough", "wheeze"] && row.symptomsSelected == ["cough"])
        #expect(row.peakFlowLPM == 420 && row.nightWaking == nil)
        #expect(row.controllerAdherence == nil)
        #expect(try context.fetch(FetchDescriptor<ContextEvent>()).map(\.id) == [V2Fixture.eventID])

        let added = DailyCheckIn(dayKey: "2026-09-22", recordedAt: V2Fixture.recordedAt, recordedTimeZoneID: "UTC",
                                 questionSetVersion: 2, symptomsPresented: [], appVersion: "1.0 (4)")
        added.controllerAdherence = "partly"
        context.insert(added)
        try context.save()
        #expect(added.schemaVersion == 3)
        // Keep the container alive: a ModelContext doesn't retain it.
        let reopenedContainer = try RespiratoryStore.makeContainer(
            configuration: ModelConfiguration(schema: RespiratoryStore.schema, url: url))
        let reopened = ModelContext(reopenedContainer)
        let adherence = try reopened.fetch(FetchDescriptor<DailyCheckIn>(sortBy: [SortDescriptor(\.dayKey)]))
            .map(\.controllerAdherence)
        #expect(adherence == [nil, "partly"])
    }

    @Test("Every current model persists and reads back its raw and composite fields after migration")
    func v2ModelsRoundTrip() throws {
        let url = try temporaryStoreURL()
        do {
            let legacy = try ModelContainer(for: UnversionedBuild2.DetectionEvent.self,
                                            configurations: ModelConfiguration(url: url))
            try ModelContext(legacy).save()
        }
        let container = try RespiratoryStore.makeContainer(
            configuration: ModelConfiguration(schema: RespiratoryStore.schema, url: url))
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let sessionID = UUID(), windowID = UUID(), observationID = UUID()

        context.insert(ListeningSession(
            id: sessionID, startedAt: now, timeZoneID: "America/Los_Angeles", sampleRate: 48_000, channelCount: 1,
            tapBufferSize: 4096, inputPortType: "MicrophoneBuiltIn", inputPortName: "iPhone Microphone",
            classifierIdentifier: "version1", windowDuration: 0.975, overlapFactor: 0.5,
            scoredLabels: ["cough", "speech"], topK: 3, captureSemanticsVersion: 2,
            appVersion: "1.0 (3)", osVersion: "26.4", deviceModel: "iPhone"))
        context.insert(ClassifierWindow(
            id: windowID, sessionID: sessionID, windowIndex: 0, startFrame: 0, durationFrames: 46_800,
            deliveredAt: now, scores: [0.4, 0.5], topLabels: ["speech", "cough", "music"],
            topScores: [0.5, 0.4, 0.05], rms: 0.02, peak: 0.3))
        context.insert(DetectionAnnotation(targetWindowID: windowID, targetLegacyEventID: nil, label: "cough",
                                           verdict: "falsePositive", createdAt: now, source: "review", appVersion: "1.0 (3)"))
        context.insert(DailyRecord(dayKey: "2026-06-01", dayStart: now, dayEnd: now.addingTimeInterval(86_400),
                                   timeZoneID: "America/Los_Angeles", utcOffsetAtStartSeconds: -25_200,
                                   firstSeenAt: now, appVersion: "1.0 (3)"))
        let observation = EnvironmentalObservation(id: observationID, provider: "googlePollen", requestKind: "forecast",
                                                    requestedAt: now, requestTimeZoneID: "America/Los_Angeles",
                                                    status: "success", parserVersion: 1, appVersion: "1.0 (3)")
        observation.rawResponse = Data(#"{"dailyInfo":[]}"#.utf8)
        observation.subIndices = ["pm25": 21, "t": 18.5]
        observation.pollenTypes = [SchemaV2.PollenIndexReading(code: "GRASS", upi: nil, category: nil, inSeason: false)]
        context.insert(observation)
        context.insert(HourlyAirQuality(observationID: observationID, provider: "googleAirQuality", hourStart: now,
                                        indexes: [SchemaV2.AirQualityIndexReading(code: "uaqi", aqi: 71, category: "Good",
                                                                                 dominantPollutant: "o3")],
                                        pollutants: [SchemaV2.PollutantConcentration(code: "pm25", value: 7.2,
                                                                                     units: "MICROGRAMS_PER_CUBIC_METER")]))
        let checkIn = DailyCheckIn(dayKey: "2026-06-01", recordedAt: now, recordedTimeZoneID: "America/Los_Angeles",
                                   questionSetVersion: 1, symptomsPresented: ["cough", "wheeze"], appVersion: "1.0 (3)")
        checkIn.rescueInhalerUses = 0
        checkIn.symptomsSelected = ["cough"]
        context.insert(checkIn)
        context.insert(ContextEvent(category: "illness", note: "cold", startDayKey: "2026-06-01", endDayKey: nil,
                                    recordedAt: now, recordedTimeZoneID: "America/Los_Angeles", appVersion: "1.0 (3)"))
        try context.save()

        let reader = ModelContext(container)
        let window = try #require(try reader.fetch(FetchDescriptor<ClassifierWindow>()).first)
        #expect(window.scores == [0.4, 0.5])
        #expect(window.topLabels == ["speech", "cough", "music"])
        let stored = try #require(try reader.fetch(FetchDescriptor<EnvironmentalObservation>()).first)
        #expect(stored.subIndices == ["pm25": 21, "t": 18.5])
        #expect(stored.pollenTypes?.first?.upi == nil)
        #expect(stored.rawResponse == Data(#"{"dailyInfo":[]}"#.utf8))
        #expect(stored.schemaVersion == RespiratoryStore.schemaVersion)
        let hour = try #require(try reader.fetch(FetchDescriptor<HourlyAirQuality>()).first)
        #expect(hour.pollutants?.first?.value == 7.2)
        let storedCheckIn = try #require(try reader.fetch(FetchDescriptor<DailyCheckIn>()).first)
        #expect(storedCheckIn.rescueInhalerUses == 0)
        #expect(storedCheckIn.nightWaking == nil)
        #expect(try reader.fetchCount(FetchDescriptor<ListeningSession>()) == 1)
        #expect(try reader.fetchCount(FetchDescriptor<DetectionAnnotation>()) == 1)
        #expect(try reader.fetchCount(FetchDescriptor<DailyRecord>()) == 1)
        #expect(try reader.fetchCount(FetchDescriptor<ContextEvent>()) == 1)
    }

    @Test("The versioned container uses the same default store file as the unversioned builds")
    func defaultStoreLocationUnchanged() {
        #expect(ModelConfiguration(schema: RespiratoryStore.schema).url == ModelConfiguration().url)
    }
}

@Suite("Store disk usage")
struct StoreDiskUsageTests {
    @Test("Counts the store, its sidecars and the external-storage folder; missing parts are zero")
    func diskUsage() throws {
        // A space in the path, like the real "Application Support" location.
        let directory = URL.temporaryDirectory.appending(path: "Application Support \(UUID().uuidString)", directoryHint: .isDirectory)
        let support = directory.appending(path: ".default_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let store = directory.appending(path: "default.store")
        try Data(count: 10_000).write(to: store)
        let empty = try #require(RespiratoryStore.diskUsage(ofStoreAt: store))
        try Data(count: 50_000).write(to: directory.appending(path: "default.store-wal"))
        try Data(count: 20_000).write(to: support.appending(path: "blob"))
        let full = try #require(RespiratoryStore.diskUsage(ofStoreAt: store))
        #expect(empty >= 10_000)
        #expect(full - empty >= 70_000)
        #expect(RespiratoryStore.diskUsage(ofStoreAt: URL(string: "https://example.com")!) == nil)  // Literal URL.
    }
}
