import SwiftUI

/// Shared semantic surfaces; system colors adapt to appearance and increased contrast.
enum AirQStyle {
    static let accent = Color("AccentColor")
    static let onAccent = Color("AccentContent")
    static let page = Color(.systemGroupedBackground)
}

struct AirQPageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.caption.weight(.semibold)).tracking(1.5)
                .foregroundStyle(AirQStyle.accent)
            Text(title).font(.title2.weight(.bold)).fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

extension View {
    func airQCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
