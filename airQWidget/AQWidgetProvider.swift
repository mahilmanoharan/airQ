//
//  AQWidgetProvider.swift
//  airQWidget
//

import WidgetKit
import AirQualityKit

/// Thin WidgetKit-conforming wrapper around `AQSnapshotEntry` from AirQualityKit.
/// The actual entry-building/scheduling logic lives in `TimelineScheduler`
/// (tested via Swift Testing in the AirQualityKit package) — this type just
/// adapts that pure data into what `TimelineProvider` requires. Shared by
/// all three widget kinds since they all read the same cached snapshot.
struct AQWidgetEntry: TimelineEntry {
    let date: Date
    let aqi: Int?
    let dominantPollutant: String?
    let pollenIndex: Int?
    let locationName: String
    let lastUpdated: Date?
    let hasData: Bool

    init(_ entry: AQSnapshotEntry) {
        date = entry.date
        aqi = entry.aqi
        dominantPollutant = entry.dominantPollutant
        pollenIndex = entry.pollenIndex
        locationName = entry.locationName
        lastUpdated = entry.lastUpdated
        hasData = entry.hasData
    }
}

struct AQWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AQWidgetEntry {
        AQWidgetEntry(
            AQSnapshotEntry(
                date: Date(),
                aqi: 42,
                dominantPollutant: "pm25",
                pollenIndex: 3,
                locationName: "Current Location",
                lastUpdated: Date(),
                hasData: true
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AQWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AQWidgetEntry>) -> Void) {
        let now = Date()
        let entries = TimelineScheduler.makeEntries(from: WidgetDataStore.loadLatest(), currentDate: now)
            .map(AQWidgetEntry.init)
        let refreshDate = TimelineScheduler.nextRefreshDate(after: now)

        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    private func currentEntry() -> AQWidgetEntry {
        let now = Date()
        let entry = TimelineScheduler.makeEntries(from: WidgetDataStore.loadLatest(), currentDate: now).first
            ?? AQSnapshotEntry(
                date: now,
                aqi: nil,
                dominantPollutant: nil,
                pollenIndex: nil,
                locationName: "Current Location",
                lastUpdated: nil,
                hasData: false
            )
        return AQWidgetEntry(entry)
    }
}
