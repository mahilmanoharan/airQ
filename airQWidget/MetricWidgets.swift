//
//  MetricWidgets.swift
//  airQWidget
//
//  The AQI and Pollen widgets: one metric each, drawn by the same views in every family.
//

import WidgetKit
import SwiftUI
import AirQualityKit

struct MetricWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AQSnapshotEntry
    let metric: WidgetMetric

    var body: some View {
        if family.isAccessory {
            if entry.hasData {
                AccessoryMetricView(isStale: entry.isStale, metric: metric, locationName: entry.locationName)
            } else {
                AccessoryNoDataView()
            }
        } else if entry.hasData, metric.value != nil || metric.showsUnavailable {
            switch family {
            case .systemMedium:
                AQStatMediumView(metric: metric, locationName: entry.locationName, lastUpdated: entry.lastUpdated,
                                 isStale: entry.isStale)
            default:
                AQStatSmallView(metric: metric, locationName: entry.locationName,
                                staleSince: entry.isStale ? entry.lastUpdated : nil)
            }
        } else {
            AQNoDataView()
        }
    }
}

struct AQIWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "airQWidget.aqi", provider: AQWidgetProvider()) { entry in
            MetricWidgetEntryView(entry: entry, metric: entry.aqiMetric)
        }
        .configurationDisplayName("AQI")
        .description("Shows the current air quality index at your last known location.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct PollenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "airQWidget.pollen", provider: AQWidgetProvider()) { entry in
            MetricWidgetEntryView(entry: entry, metric: entry.pollenMetric)
        }
        .configurationDisplayName("Pollen")
        .description("Shows the current pollen index at your last known location.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    AQIWidget()
} timeline: {
    AQSnapshotEntry.preview
    AQSnapshotEntry.previewEmpty
}

#Preview(as: .accessoryCircular) {
    AQIWidget()
} timeline: {
    AQSnapshotEntry.preview
}

#Preview(as: .systemMedium) {
    AQIWidget()
} timeline: {
    AQSnapshotEntry(date: .now, aqi: 156, dominantPollutant: "o3", pollenIndex: 4, locationName: "San Francisco", lastUpdated: .now.addingTimeInterval(-900), hasData: true,
                    tomorrow: .init(day: "2026-09-29", pollutants: ["pm25": .init(min: 22, average: 33, max: 68)], uvIndex: nil))
}

#Preview(as: .systemSmall) {
    PollenWidget()
} timeline: {
    AQSnapshotEntry.preview
    AQSnapshotEntry.previewEmpty
}
