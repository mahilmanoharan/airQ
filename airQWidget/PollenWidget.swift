//
//  PollenWidget.swift
//  airQWidget
//

import WidgetKit
import SwiftUI
import AirQualityKit

struct PollenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AQWidgetEntry

    var body: some View {
        if entry.hasData, let pollenIndex = entry.pollenIndex {
            switch family {
            case .systemMedium:
                AQStatMediumView(
                    value: pollenIndex,
                    label: "Pollen",
                    category: PollenPresentation.category(for: pollenIndex),
                    color: PollenPresentation.color(for: pollenIndex),
                    locationName: entry.locationName,
                    lastUpdated: entry.lastUpdated
                )
            default:
                AQStatSmallView(
                    value: pollenIndex,
                    label: "Pollen",
                    category: PollenPresentation.category(for: pollenIndex),
                    color: PollenPresentation.color(for: pollenIndex),
                    locationName: entry.locationName
                )
            }
        } else {
            AQNoDataView()
        }
    }
}

struct PollenWidget: Widget {
    let kind: String = "airQWidget.pollen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AQWidgetProvider()) { entry in
            PollenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pollen")
        .description("Shows the current pollen index at your last known location.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    PollenWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 42, dominantPollutant: "pm25", pollenIndex: 2, locationName: "San Francisco", lastUpdated: .now, hasData: true))
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: nil, dominantPollutant: nil, pollenIndex: nil, locationName: "Current Location", lastUpdated: nil, hasData: false))
}

#Preview(as: .systemMedium) {
    PollenWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 156, dominantPollutant: "o3", pollenIndex: 4, locationName: "San Francisco", lastUpdated: .now.addingTimeInterval(-900), hasData: true))
}
