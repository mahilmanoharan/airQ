//
//  CombinedWidget.swift
//  airQWidget
//

import WidgetKit
import SwiftUI
import AirQualityKit

struct CombinedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AQSnapshotEntry

    var body: some View {
        if family.isAccessory {
            if entry.hasData {
                AccessoryCombinedView(aqi: entry.aqiMetric, pollen: entry.pollenMetric, locationName: entry.locationName,
                                      isStale: entry.isStale)
            } else {
                AccessoryNoDataView()
            }
        } else if entry.hasData, entry.aqi != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.locationName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    stat(entry.aqiMetric, label: "AQI")
                    stat(entry.pollenMetric, label: entry.pollenIsTomorrowsForecast ? "Pollen (tmrw)" : "Pollen")
                }

                if let lastUpdated = entry.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(entry.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            AQNoDataView()
        }
    }

    private func stat(_ metric: WidgetMetric, label: String) -> some View {
        VStack(spacing: 4) {
            Text(metric.value.map(String.init) ?? "—")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(metric.color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(metric.category)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(metric.color.opacity(0.15))
        )
    }
}

struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "airQWidget.combined", provider: AQWidgetProvider()) { entry in
            CombinedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AQI & Pollen")
        .description("Shows both the air quality index and pollen index side by side.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemMedium) {
    CombinedWidget()
} timeline: {
    AQSnapshotEntry.preview
    AQSnapshotEntry.previewEmpty
}
