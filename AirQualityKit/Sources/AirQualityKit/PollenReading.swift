import Foundation

/// A resolved pollen reading in our own units (Google's 0–5 Universal Pollen
/// Index scale), independent of whichever provider's response shape produced
/// it. Every call site (app UI, widget) depends on this, not a provider type.
public struct PollenReading: Codable, Sendable, Equatable {
    /// The single at-a-glance value: the highest of grass/tree/weed, not an
    /// average — a day that's mild on two types but severe on one should
    /// still read as severe, the same way AQI is driven by its worst pollutant.
    public let overallIndex: Int
    public let grassIndex: Int
    public let treeIndex: Int
    public let weedIndex: Int

    public init(grassIndex: Int, treeIndex: Int, weedIndex: Int) {
        self.grassIndex = grassIndex
        self.treeIndex = treeIndex
        self.weedIndex = weedIndex
        self.overallIndex = max(grassIndex, treeIndex, weedIndex)
    }
}
