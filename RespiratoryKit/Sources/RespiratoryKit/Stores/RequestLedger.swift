import Foundation

/// The times of airQ's own metered provider requests, kept outside the record store so an erase
/// can't reset the free-tier usage count. It holds only the provider name and when a request was
/// made: no places, readings, bodies or anything about the person. Entries older than the budget
/// window are dropped as they're written.
public enum RequestLedger {
    static let key = "airQRequestLedger"
    /// A little longer than the 31-day budget window, so an entry never expires early.
    static let retention: TimeInterval = 32 * 24 * 60 * 60

    public static func add(_ entries: [String: [Date]], to defaults: UserDefaults = .standard, now: Date = Date()) {
        var stored = read(defaults)
        for (provider, dates) in entries { stored[provider, default: []] += dates.map(\.timeIntervalSince1970) }
        let cutoff = now.addingTimeInterval(-retention).timeIntervalSince1970
        stored = stored.mapValues { $0.filter { $0 >= cutoff } }.filter { !$0.value.isEmpty }
        defaults.set(stored, forKey: key)
    }

    public static func count(provider: String, since date: Date, in defaults: UserDefaults = .standard) -> Int {
        let start = date.timeIntervalSince1970
        return read(defaults)[provider, default: []].count { $0 >= start }
    }

    public static func latest(provider: String, in defaults: UserDefaults = .standard) -> Date? {
        read(defaults)[provider]?.max().map(Date.init(timeIntervalSince1970:))
    }

    private static func read(_ defaults: UserDefaults) -> [String: [Double]] {
        defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}
