import SwiftUI

/// Shared semantic surfaces; system colors adapt to appearance and increased contrast.
enum AirQStyle {
    static let accent = Color("AccentColor")
    static let onAccent = Color("AccentContent")
    static let page = Color(.systemGroupedBackground)

    static let surface = Color(.secondarySystemGroupedBackground)
    static let cardRadius: CGFloat = 12

    static var background: some View { page.ignoresSafeArea() }
}

struct AirQPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(AirQStyle.onAccent)
            .background(
                AirQStyle.accent.opacity(configuration.isPressed ? 0.75 : 1),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct AirQPageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.caption.weight(.semibold)).tracking(1.5)
                .foregroundStyle(AirQStyle.accent)
            Text(title).font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

extension View {
    func airQActionBar() -> some View {
        frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }

    func airQCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AirQStyle.surface, in: RoundedRectangle(cornerRadius: AirQStyle.cardRadius))
    }
}
