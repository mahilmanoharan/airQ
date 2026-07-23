//
//  CombinedWidget.swift
//  airQWidget
//

import WidgetKit
import SwiftUI
import AirQualityKit

struct CombinedWidgetEntryView: View {
    var entry: AQWidgetEntry

    var body: some View {
        if entry.hasData, let aqi = entry.aqi, let pollenIndex = entry.pollenIndex {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.locationName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    stat(value: aqi, label: "AQI", category: AirQualityPresentation.category(for: aqi), color: AirQualityPresentation.color(for: aqi))
                    stat(value: pollenIndex, label: "Pollen", category: PollenPresentation.category(for: pollenIndex), color: PollenPresentation.color(for: pollenIndex))
                }

                if let lastUpdated = entry.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            AQNoDataView()
        }
    }

    private func stat(value: Int, label: String, category: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(category)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.15))
        )
    }
}

struct CombinedWidget: Widget {
    let kind: String = "airQWidget.combined"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AQWidgetProvider()) { entry in
            CombinedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AQI & Pollen")
        .description("Shows both the air quality index and pollen index side by side.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    CombinedWidget()
} timeline: {
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: 42, dominantPollutant: "pm25", pollenIndex: 2, locationName: "San Francisco", lastUpdated: .now, hasData: true))
    AQWidgetEntry(AQSnapshotEntry(date: .now, aqi: nil, dominantPollutant: nil, pollenIndex: nil, locationName: "Current Location", lastUpdated: nil, hasData: false))
}
