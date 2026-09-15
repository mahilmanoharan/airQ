import Foundation
import Testing
@testable import RespiratoryKit

private func snapshot(
    _ offset: TimeInterval,
    label: String = "cough",
    confidence: Double = 0.8,
    isFalsePositive: Bool = false
) -> DetectionSnapshot {
    DetectionSnapshot(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
        label: label,
        confidence: confidence,
        isFalsePositive: isFalsePositive
    )
}

@Suite("DetectionAnalysis.filterByThreshold")
struct FilterByThresholdTests {
    @Test("Excludes events below the confidence threshold")
    func excludesLowConfidence() {
        let snapshots = [snapshot(0, confidence: 0.9), snapshot(1, confidence: 0.2)]

        let result = DetectionAnalysis.filterByThreshold(snapshots, threshold: 0.5)

        #expect(result.count == 1)
        #expect(result[0].confidence == 0.9)
    }

    @Test("Excludes events marked as false positives regardless of confidence")
    func excludesFalsePositives() {
        let snapshots = [snapshot(0, confidence: 0.95, isFalsePositive: true)]

        let result = DetectionAnalysis.filterByThreshold(snapshots, threshold: 0.1)

        #expect(result.isEmpty)
    }

    @Test("Includes events exactly at the threshold")
    func includesBoundary() {
        let snapshots = [snapshot(0, confidence: 0.5)]

        let result = DetectionAnalysis.filterByThreshold(snapshots, threshold: 0.5)

        #expect(result.count == 1)
    }
}

@Suite("DetectionAnalysis.debounce")
struct DebounceTests {
    @Test("Collapses same-label detections closer than the gap into one, keeping the higher confidence")
    func collapsesOverlappingWindows() {
        let snapshots = [
            snapshot(0.0, confidence: 0.6),
            snapshot(0.3, confidence: 0.9),
            snapshot(0.6, confidence: 0.7),
        ]

        let result = DetectionAnalysis.debounce(snapshots, minInterEventGap: 1.0)

        #expect(result.count == 1)
        #expect(result[0].confidence == 0.9)
    }

    @Test("Does not collapse events further apart than the gap")
    func keepsDistantEvents() {
        let snapshots = [snapshot(0), snapshot(5)]

        let result = DetectionAnalysis.debounce(snapshots, minInterEventGap: 1.0)

        #expect(result.count == 2)
    }

    @Test("Does not collapse different labels even when close together")
    func keepsDifferentLabelsSeparate() {
        let snapshots = [snapshot(0, label: "cough"), snapshot(0.2, label: "sneeze")]

        let result = DetectionAnalysis.debounce(snapshots, minInterEventGap: 1.0)

        #expect(result.count == 2)
    }

    @Test("Handles an empty input")
    func handlesEmpty() {
        #expect(DetectionAnalysis.debounce([], minInterEventGap: 1.0).isEmpty)
    }
}

@Suite("DetectionAnalysis.cluster")
struct ClusterTests {
    @Test("Groups events within the bout gap into one bout")
    func groupsCloseEvents() {
        let events = [
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 0), label: "cough", confidence: 0.8),
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 4), label: "cough", confidence: 0.8),
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 8), label: "cough", confidence: 0.8),
        ]

        let bouts = DetectionAnalysis.cluster(events, boutGapThreshold: 10)

        #expect(bouts.count == 1)
        #expect(bouts[0].count == 3)
    }

    @Test("Splits events further apart than the bout gap into separate bouts")
    func splitsDistantEvents() {
        let events = [
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 0), label: "cough", confidence: 0.8),
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 100), label: "cough", confidence: 0.8),
        ]

        let bouts = DetectionAnalysis.cluster(events, boutGapThreshold: 10)

        #expect(bouts.count == 2)
        #expect(bouts[0].count == 1)
        #expect(bouts[1].count == 1)
    }

    @Test("Retuning the bout gap changes clustering over the same events, with no data mutation")
    func retuningChangesClusteringOverSameData() {
        let events = [
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 0), label: "cough", confidence: 0.8),
            DebouncedEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: 8), label: "cough", confidence: 0.8),
        ]

        let tightBouts = DetectionAnalysis.cluster(events, boutGapThreshold: 5)
        let looseBouts = DetectionAnalysis.cluster(events, boutGapThreshold: 10)

        #expect(tightBouts.count == 2)
        #expect(looseBouts.count == 1)
    }

    @Test("Handles an empty input")
    func handlesEmpty() {
        #expect(DetectionAnalysis.cluster([], boutGapThreshold: 10).isEmpty)
    }
}
