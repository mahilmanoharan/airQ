//
//  AQIWidget.swift
//  airQWidget
//

import WidgetKit
import SwiftUI
import AirQualityKit

struct AQIWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AQWidgetEntry

    var body: some View {
        if entry.hasData, let aqi = entry.aqi {
            switch family {
            case .systemMedium:
                AQStatMediumView(
                    value: aqi,
                    label: "AQI",
                    category: AirQualityPresentation.category(for: aqi),
                    color: AirQualityPresentation.color(for: aqi),
                    locationName: entry.locationName,
                    lastUpdated: entry.lastUpdated
                )
            default:
                AQStatSmallView(
                    value: aqi,
                    label: "AQI",
                    category: AirQualityPresentation.category(for: aqi),
                    color: AirQualityPresentation.color(for: aqi),
                    locationName: entry.locationName
                )
            }
        } else {
            AQNoDataView()
        }
    }
}

struct AQIWidget: Widget {
    let kind: String = "airQWidget.aqi"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AQWidgetProvider()) { entry in
            AQIWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AQI")
        .description("Shows the current air quality index at your last known location.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    AQIWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 42, dominantPollutant: "pm25", pollenIndex: 2, locationName: "San Francisco", lastUpdated: .now, hasData: true))
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: nil, dominantPollutant: nil, pollenIndex: nil, locationName: "Current Location", lastUpdated: nil, hasData: false))
}

#Preview(as: .systemMedium) {
    AQIWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 156, dominantPollutant: "o3", pollenIndex: 4, locationName: "San Francisco", lastUpdated: .now.addingTimeInterval(-900), hasData: true))
}
