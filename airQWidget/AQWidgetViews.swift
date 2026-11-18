//
//  AQWidgetViews.swift
//  airQWidget
//
//  Shared layout building blocks so the AQI and Pollen widgets render with the
//  same visual treatment, and so the widget never reimplements the color-coded
//  severity styling that already lives in AirQualityPresentation/PollenPresentation.
//

import SwiftUI
import WidgetKit

struct AQStatSmallView: View {
    let metric: WidgetMetric
    let locationName: String
    /// When set, the reading is old enough to flag (the app only refreshes when opened).
    var staleSince: Date? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(metric.value.map(String.init) ?? "—")
                .font(.system(size: 44, weight: .bold))
            // The word carries the meaning, so it is the most prominent text after the number.
            Text(metric.category)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(metric.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let staleSince {
                Label { Text(staleSince, style: .relative) } icon: { Image(systemName: "clock") }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .accessibilityLabel("Reading is old")
            } else {
                Text(locationName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(metric.color.opacity(0.15), for: .widget)
    }
}

struct AQStatMediumView: View {
    let metric: WidgetMetric
    let locationName: String
    let lastUpdated: Date?
    var isStale = false

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(metric.value.map(String.init) ?? "—")
                    .font(.system(size: 48, weight: .bold))
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(locationName)
                    .font(.headline)
                    .lineLimit(2)
                Text(metric.category)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let footnote = metric.footnote {
                    Text(footnote)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(metric.color.opacity(0.15), for: .widget)
    }
}

struct AQNoDataView: View {
    var message = "Open airQ to load air quality data"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "aqi.medium")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
