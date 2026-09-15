import Testing
@testable import RespiratoryKit

@Suite("SoundClassifierProbe")
struct SoundClassifierProbeTests {
    @Test("Built-in classifier exposes a non-empty label list")
    func knownClassificationsIsNonEmpty() throws {
        let labels = try SoundClassifierProbe.knownClassifications()
        #expect(!labels.isEmpty)

        print("Known classifications (\(labels.count)):")
        for label in labels.sorted() {
            print(" - \(label)")
        }
    }
}
