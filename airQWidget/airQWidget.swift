//
//  airQWidget.swift
//  airQWidget
//
//  Created by Mahil Manoharan on 7/18/26.
//

import WidgetKit
import SwiftUI
import AirQualityKit

// MARK: - Entry

/// Thin WidgetKit-conforming wrapper around `AQSnapshotEntry` from AirQualityKit.
/// The actual entry-building/scheduling logic lives in `TimelineScheduler`
/// (tested via Swift Testing in the AirQualityKit package) — this type just
/// adapts that pure data into what `TimelineProvider` requires.
struct AQWidgetEntry: TimelineEntry {
    let date: Date
    let aqi: Int?
    let locationName: String
    let lastUpdated: Date?
    let hasData: Bool

    init(_ entry: AQSnapshotEntry) {
        date = entry.date
        aqi = entry.aqi
        locationName = entry.locationName
        lastUpdated = entry.lastUpdated
        hasData = entry.hasData
    }
}

// MARK: - Provider

struct AQWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AQWidgetEntry {
        AQWidgetEntry(
            AQSnapshotEntry(date: Date(), aqi: 42, locationName: "Current Location", lastUpdated: Date(), hasData: true)
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
            ?? AQSnapshotEntry(date: now, aqi: nil, locationName: "Current Location", lastUpdated: nil, hasData: false)
        return AQWidgetEntry(entry)
    }
}

// MARK: - Views

struct airQWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AQWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    @ViewBuilder
    private var smallView: some View {
        if entry.hasData, let aqi = entry.aqi {
            VStack(spacing: 8) {
                Text("\(aqi)")
                    .font(.system(size: 44, weight: .bold))
                Text("AQI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AirQualityPresentation.category(for: aqi))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Text(entry.locationName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(AirQualityPresentation.color(for: aqi).opacity(0.15), for: .widget)
        } else {
            noDataView
        }
    }

    @ViewBuilder
    private var mediumView: some View {
        if entry.hasData, let aqi = entry.aqi {
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(aqi)")
                        .font(.system(size: 48, weight: .bold))
                    Text("AQI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.locationName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(AirQualityPresentation.category(for: aqi))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let lastUpdated = entry.lastUpdated {
                        Text("Updated \(lastUpdated, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(AirQualityPresentation.color(for: aqi).opacity(0.15), for: .widget)
        } else {
            noDataView
        }
    }

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "aqi.medium")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open airQ to load air quality data")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct airQWidget: Widget {
    let kind: String = "airQWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AQWidgetProvider()) { entry in
            airQWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Air Quality")
        .description("Shows the current AQI at your last known location.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    airQWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 42, locationName: "San Francisco", lastUpdated: .now, hasData: true))
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: nil, locationName: "Current Location", lastUpdated: nil, hasData: false))
}

#Preview(as: .systemMedium) {
    airQWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 156, locationName: "San Francisco-Arkansas Street, San Francisco, California", lastUpdated: .now.addingTimeInterval(-900), hasData: true))
}
