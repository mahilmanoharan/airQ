import Foundation
import SwiftData
import Testing
@testable import RespiratoryKit

@Suite("DetectionStore")
struct DetectionStoreTests {
    private func makeStore() throws -> DetectionStore {
        let schema = Schema([DetectionEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return DetectionStore(modelContainer: container)
    }

    private static let testConfig = DetectionConfig(
        windowDuration: 1.0,
        overlapFactor: 0.5,
        classifierIdentifier: "version1",
        appVersion: "1.0 (1)"
    )

    @Test("Records a detection and fetches it back with the correct raw fields")
    func recordsAndFetches() async throws {
        let store = try makeStore()

        try await store.record(
            sessionID: UUID(),
            label: "cough",
            confidence: 0.8,
            timestamp: Date(),
            config: Self.testConfig
        )

        let snapshots = try await store.fetchAllSnapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].label == "cough")
        #expect(snapshots[0].confidence == 0.8)
        #expect(snapshots[0].isFalsePositive == false)
    }

    @Test("Marking false positive persists and is reflected in a fresh fetch")
    func marksFalsePositive() async throws {
        let store = try makeStore()
        let sessionID = UUID()

        try await store.record(
            sessionID: sessionID,
            label: "cough",
            confidence: 0.8,
            timestamp: Date(),
            config: Self.testConfig
        )
        let firstFetch = try await store.fetchAllSnapshots()
        let id = try #require(firstFetch.first?.id)

        try await store.setFalsePositive(id, isFalsePositive: true)
        let secondFetch = try await store.fetchAllSnapshots()

        #expect(secondFetch.first?.isFalsePositive == true)
    }

    @Test("Multiple events are returned sorted by timestamp")
    func returnsSortedByTimestamp() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        let now = Date()

        try await store.record(
            sessionID: sessionID,
            label: "sneeze",
            confidence: 0.6,
            timestamp: now.addingTimeInterval(10),
            config: Self.testConfig
        )
        try await store.record(
            sessionID: sessionID,
            label: "cough",
            confidence: 0.9,
            timestamp: now,
            config: Self.testConfig
        )

        let snapshots = try await store.fetchAllSnapshots()
        #expect(snapshots.map(\.label) == ["cough", "sneeze"])
        let recent = try await store.fetchSnapshots(limit: 1, newestFirst: true)
        #expect(recent.map(\.label) == ["sneeze"])
    }
}
