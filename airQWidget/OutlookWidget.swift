//
//  OutlookWidget.swift
//  airQWidget
//
//  The next few days side by side: WAQI's forecast peak and Google's pollen outlook, both from the
//  snapshot the app last saved (no request is made for the widget).
//

import WidgetKit
import SwiftUI
import AirQualityKit

struct OutlookWidgetEntryView: View {
    let entry: AQSnapshotEntry

    var body: some View {
        if entry.hasData, !entry.outlook.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.locationName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if entry.isStale, let updated = entry.lastUpdated {
                        Label { Text(updated, style: .relative) } icon: { Image(systemName: "clock") }
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(entry.outlook) { day in
                        OutlookColumn(day: day, entryDate: entry.date)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        } else if entry.hasData {
            // A reading exists but it carries no forecast (older saved readings, stations without one).
            AQNoDataView(message: "No forecast for the next few days is available yet")
        } else {
            AQNoDataView()
        }
    }
}

private struct OutlookColumn: View {
    let day: OutlookDay
    /// Labels are relative to the entry's date, not render time (entries are precomputed for midnight).
    let entryDate: Date

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2.weight(.semibold)).lineLimit(1)
            metric(value: day.aqiPeak, caption: "AQI",
                   color: day.aqiPeak.map(AirQualityPresentation.color(for:)) ?? .secondary)
            metric(value: day.pollenIndex, caption: "Pollen", color: PollenPresentation.color(for: day.pollenIndex))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([day.aqiPeak.map { "AQI up to \($0), \(AirQualityPresentation.category(for: $0))" },
                             day.pollenIndex.map { "pollen \($0) of 5" }].compactMap(\.self).joined(separator: ", "))
    }

    private func metric(value: Int?, caption: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value.map(String.init) ?? "—").font(.headline).foregroundStyle(color)
            Text(caption).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
    }

    private var label: String { DayKey.label(day.dayKey, relativeTo: entryDate) }
}

struct OutlookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "airQWidget.outlook", provider: AQWidgetProvider()) { entry in
            OutlookWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Outlook")
        .description("The next few days of forecast air quality and pollen.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    OutlookWidget()
} timeline: {
    AQSnapshotEntry(date: .now, aqi: 34, dominantPollutant: "pm25", pollenIndex: 1, locationName: "San Francisco",
                    lastUpdated: .now, hasData: true,
                    outlook: [.init(dayKey: DayKey.local(.now), aqiPeak: 51, pollenIndex: 1),
                              .init(dayKey: "2099-01-02", aqiPeak: 68, pollenIndex: 2),
                              .init(dayKey: "2099-01-03", aqiPeak: nil, pollenIndex: 2),
                              .init(dayKey: "2099-01-04", aqiPeak: 24, pollenIndex: nil)])
}
