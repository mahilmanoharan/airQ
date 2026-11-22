import SwiftUI

/// Shown once, before airQ asks to use the location: what the app is, what is optional, and where
/// the data lives, in plain words. Nothing to configure.
struct WelcomeView: View {
    /// Bump to show it again after a change that people should hear about.
    static let currentVersion = 2

    static let versionKey = "welcomeVersion"

    /// Whether to show it at launch: once per version. UI tests and debug launches that open a specific
    /// screen skip it; `-showWelcome YES` forces it (for that launch only).
    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        if defaults.bool(forKey: "showWelcome") { return true }
        if AppServices.isUITesting || !AppRoute.initialPath.isEmpty { return false }
        #endif
        return defaults.integer(forKey: versionKey) < currentVersion
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: versionKey)
    }

    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to airQ").font(.largeTitle.bold())
                    Text("Check the air near you and keep track of how you feel.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                WelcomePoint(symbol: "aqi.medium", title: "Air and pollen, in plain words",
                             text: "airQ finds the nearest air quality station and today's pollen forecast, and tells you what they mean.")
                WelcomePoint(symbol: "location", title: "Your approximate location",
                             text: "After you tap Get started, airQ asks for location access. It uses your approximate area to find local air quality and pollen.")
                WelcomePoint(symbol: "heart.text.clipboard", title: "Track how you feel",
                             text: "An optional daily check-in helps you see symptoms beside air quality and pollen in History.")
                WelcomePoint(symbol: "lock", title: "Your notes stay on this iPhone",
                             text: "There's no account. Preview a report for your clinician, or export and erase your record at any time.")
                Text("airQ shows information. It doesn't diagnose anything or give medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: 560, minHeight: 48)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(AirQStyle.onAccent)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .background(Color(.systemBackground))
    }
}

private struct WelcomePoint: View {
    let symbol: String
    let title: String
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var iconWidth = 36.0

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: iconWidth, alignment: stacked ? .leading : .center)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.body)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
