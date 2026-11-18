//
//  ScreenControls.swift
//  airQWidget
//
//  Control Center, Lock Screen and Action button controls. Each opens airQ on one screen; the air
//  quality control also shows the saved reading (the cache the widgets read, so it never makes a request).
//

import AppIntents
import SwiftUI
import WidgetKit
import AirQualityKit

struct AirQualityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "airQWidget.control.airQuality", provider: Provider()) { reading in
            ControlWidgetButton(action: OpenScreenControlIntent(.dashboard)) {
                Label(reading.title, systemImage: "aqi.medium")
            }
        }
        .displayName("Air Quality")
        .description("Shows the last saved AQI and opens airQ.")
    }

    /// The saved AQI, flagged "old" past the same age the widgets flag.
    struct Reading: Sendable {
        let aqi: Int?
        let isStale: Bool

        var title: String {
            guard let aqi else { return "Air quality" }
            return "AQI \(aqi) · \(isStale ? "old reading" : AirQualityPresentation.category(for: aqi))"
        }
    }

    struct Provider: ControlValueProvider {
        var previewValue: Reading { Reading(aqi: 42, isStale: false) }

        func currentValue() async throws -> Reading {
            let snapshot = WidgetDataStore.loadLatest()
            let age = snapshot.map { Date().timeIntervalSince($0.lastUpdated) } ?? 0
            return Reading(aqi: snapshot?.aqi, isStale: age >= AQSnapshot.staleAfter)
        }
    }
}

struct CheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        screenControl(.checkIn, title: "Daily Check-in", systemImage: "checklist",
                      description: "Opens today's check-in.")
    }
}

struct ListenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        screenControl(.listen, title: "Listen for Coughs", systemImage: "waveform",
                      description: "Opens Listen. Listening starts only when you press Start.")
    }
}

struct LifeEventControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        screenControl(.contextEvents, title: "Life Events", systemImage: "calendar.badge.plus",
                      description: "Opens life events, to note a medication change, illness, travel or a move.")
    }
}

@MainActor
private func screenControl(_ screen: ControlScreen, title: LocalizedStringResource, systemImage: String,
                           description: LocalizedStringResource) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "airQWidget.control.\(screen.rawValue)") {
        ControlWidgetButton(action: OpenScreenControlIntent(screen)) {
            Label(String(localized: title), systemImage: systemImage)
        }
    }
    .displayName(title)
    .description(description)
}
