import Foundation
import Testing
@testable import AirQualityKit

@Suite("Spoken summary")
struct AirQualitySummaryTests {
    private let now = Date(timeIntervalSince1970: 100_000)

    private func snapshot(pollen: Int?, age: TimeInterval, aqi: Int = 34, pollutant: String? = "pm25") -> AQSnapshot {
        AQSnapshot(aqi: aqi, dominantPollutant: pollutant, pollenIndex: pollen, locationName: "San Francisco",
                   lastUpdated: now.addingTimeInterval(-age))
    }

    @Test("A recent reading states AQI and pollen categories")
    func recent() {
        #expect(AirQualitySummary.sentence(for: snapshot(pollen: 4, age: 600), asOf: now)
                == "The air quality index in San Francisco is 34, good, and pollen is high.")
    }

    @Test("Unavailable pollen is omitted rather than reported as none")
    func noPollen() {
        #expect(AirQualitySummary.sentence(for: snapshot(pollen: nil, age: 0), asOf: now)
                == "The air quality index in San Francisco is 34, good.")
    }

    @Test("The main pollutant is named only above Good, and only when it is a known code")
    func dominantPollutant() {
        #expect(AirQualitySummary.sentence(for: snapshot(pollen: nil, age: 0, aqi: 75), asOf: now)
                == "The air quality index in San Francisco is 75, moderate, mainly fine particles, PM 2.5.")
        #expect(!AirQualitySummary.sentence(for: snapshot(pollen: nil, age: 0, aqi: 75, pollutant: "xyz"), asOf: now)
            .contains("mainly"))
    }

    @Test("An old reading says how old it is; no reading asks to open the app")
    func staleAndMissing() {
        let stale = AirQualitySummary.sentence(for: snapshot(pollen: 1, age: 5 * 3_600 + 60), asOf: now)
        #expect(stale.hasSuffix("That reading is 5 hours old; open airQ to refresh it."))
        #expect(AirQualitySummary.sentence(for: nil, asOf: now).contains("no reading"))
    }

    @Test("Advice appends the EPA guidance for the AQI, and only the open-airQ line without a reading")
    func advice() {
        let text = AirQualitySummary.advice(for: snapshot(pollen: nil, age: 0, aqi: 120), asOf: now)
        #expect(text.hasSuffix(AirQualityPresentation.guidance(for: 120)))
        #expect(text.hasPrefix("The air quality index in San Francisco is 120"))
        #expect(AirQualitySummary.advice(for: nil, asOf: now) == AirQualitySummary.sentence(for: nil, asOf: now))
    }
}
