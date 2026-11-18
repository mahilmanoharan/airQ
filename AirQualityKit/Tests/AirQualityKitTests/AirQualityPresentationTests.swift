import Testing
@testable import AirQualityKit

@Suite("Air quality and pollen presentation")
struct AirQualityPresentationTests {
    @Test("Each US AQI category starts exactly at its breakpoint")
    func breakpoints() {
        let expected: [(Int, String)] = [
            (0, "Good"), (50, "Good"), (51, "Moderate"), (100, "Moderate"),
            (101, "Unhealthy for Sensitive Groups"), (150, "Unhealthy for Sensitive Groups"),
            (151, "Unhealthy"), (200, "Unhealthy"), (201, "Very Unhealthy"), (300, "Very Unhealthy"),
            (301, "Hazardous"), (500, "Hazardous"), (10_000, "Hazardous"),
        ]
        for (aqi, category) in expected { #expect(AirQualityPresentation.category(for: aqi) == category, "AQI \(aqi)") }
    }

    @Test("Bands are contiguous with no gap or overlap, so every AQI has one category")
    func contiguous() {
        let bands = AirQualityPresentation.bands
        #expect(bands.first?.range.lowerBound == 0)
        for (previous, next) in zip(bands, bands.dropFirst()) {
            #expect(previous.range.upperBound + 1 == next.range.lowerBound)
        }
        #expect(bands.last?.range.upperBound == Int.max)
        #expect(bands.allSatisfy { !$0.guidance.isEmpty })
    }

    @Test("A negative index (never valid) falls back to Good rather than crashing")
    func negative() {
        #expect(AirQualityPresentation.category(for: -5) == "Good")
    }

    @Test("Pollen categories follow the 0–5 universal index; nil is unavailable, never none")
    func pollen() {
        let names = (0...5).map { PollenPresentation.category(for: $0) }
        #expect(names == ["None", "Very Low", "Low", "Moderate", "High", "Very High"])
        #expect(PollenPresentation.category(for: 9) == "Very High")
        #expect(PollenPresentation.category(for: nil) == "Unavailable")
        #expect(PollenPresentation.guidance(for: nil).contains("unavailable"))
        #expect((0...5).allSatisfy { !PollenPresentation.guidance(for: $0).isEmpty })
    }
}
