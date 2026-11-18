//
//  AQWidgetProvider.swift
//  airQWidget
//

import WidgetKit
import AirQualityKit

/// Widgets use AirQualityKit's entry directly; building and scheduling entries lives in the tested
/// `TimelineScheduler`, so the provider only adapts it to WidgetKit. Shared by every widget kind.
extension AQSnapshotEntry: @retroactive TimelineEntry {
    static let preview = AQSnapshotEntry(date: .now, aqi: 42, dominantPollutant: "pm25", pollenIndex: 2,
                                         locationName: "San Francisco", lastUpdated: .now, hasData: true)
    static let previewEmpty = AQSnapshotEntry(date: .now, aqi: nil, dominantPollutant: nil, pollenIndex: nil,
                                              locationName: "Current Location", lastUpdated: nil, hasData: false)
}

struct AQWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AQSnapshotEntry {
        AQSnapshotEntry(date: Date(), aqi: 42, dominantPollutant: "pm25", pollenIndex: 3,
                        locationName: "Current Location", lastUpdated: Date(), hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AQSnapshotEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AQSnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetDataStore.loadLatest()
        let entries = TimelineScheduler.makeEntries(from: snapshot, currentDate: now)
        let refreshDate = TimelineScheduler.nextRefreshDate(after: now, snapshot: snapshot)

        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    private func currentEntry() -> AQSnapshotEntry {
        let now = Date()
        return TimelineScheduler.makeEntries(from: WidgetDataStore.loadLatest(), currentDate: now).first
            ?? AQSnapshotEntry(date: now, aqi: nil, dominantPollutant: nil, pollenIndex: nil,
                               locationName: "Current Location", lastUpdated: nil, hasData: false)
    }
}
