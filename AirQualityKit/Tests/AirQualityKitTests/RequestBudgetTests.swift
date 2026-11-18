import Foundation
import Testing
@testable import AirQualityKit

@Suite("Rolling request budget")
struct RequestBudgetTests {
    private let now = Date(timeIntervalSince1970: 100 * 86_400)

    @Test("Permits requests below the limit")
    func belowLimit() async {
        let budget = RollingRequestBudget(limits: [.googlePollen: 2]) { _, _ in 1 }
        #expect(await budget.permits(.googlePollen, at: now))
    }

    @Test("Refuses once the limit is reached")
    func atLimit() async {
        let budget = RollingRequestBudget(limits: [.googlePollen: 2]) { _, _ in 2 }
        #expect(await budget.permits(.googlePollen, at: now) == false)
    }

    @Test("Unmetered providers are always permitted")
    func unmetered() async {
        let budget = RollingRequestBudget(limits: [.googlePollen: 0]) { _, _ in 999 }
        #expect(await budget.permits(.waqi, at: now))
    }

    @Test("If usage can't be counted, nothing is spent")
    func countFailureRefuses() async {
        let budget = RollingRequestBudget(limits: [.googlePollen: 10]) { _, _ in throw CocoaError(.fileReadUnknown) }
        #expect(await budget.permits(.googlePollen, at: now) == false)
    }

    @Test("Usage is counted over the preceding 31 days")
    func windowStart() async {
        let box = DateBox()
        let budget = RollingRequestBudget(limits: [.googleAirQuality: 5]) { _, since in
            await box.set(since)
            return 0
        }
        _ = await budget.permits(.googleAirQuality, at: now)
        #expect(await box.value == now.addingTimeInterval(-31 * 86_400))
    }

    @Test("Default limits stay far inside Google's free tiers")
    func defaults() {
        #expect(RollingRequestBudget.freeTierSafeLimits == [.googleAirQuality: 300, .googlePollen: 1_000])
    }
}

private actor DateBox {
    var value: Date?
    func set(_ date: Date) { value = date }
}
