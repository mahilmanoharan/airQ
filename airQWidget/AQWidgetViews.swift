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
    let value: Int
    let label: String
    let category: String
    let color: Color
    let locationName: String

    var body: some View {
        VStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 44, weight: .bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(category)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text(locationName)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(color.opacity(0.15), for: .widget)
    }
}

struct AQStatMediumView: View {
    let value: Int
    let label: String
    let category: String
    let color: Color
    let locationName: String
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 48, weight: .bold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(locationName)
                    .font(.headline)
                    .lineLimit(2)
                Text(category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(color.opacity(0.15), for: .widget)
    }
}

struct AQNoDataView: View {
    var body: some View {
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
