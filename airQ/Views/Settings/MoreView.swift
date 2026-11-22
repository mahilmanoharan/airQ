import SwiftUI

struct MoreView: View {
    @ScaledMetric(relativeTo: .title3) private var iconSize = 36.0

    private func subtitle(_ route: AppRoute) -> String {
        switch route {
        case .contextEvents: "Note travel, illness or changes in routine"
        case .alerts: "Choose when airQ lets you know about the air"
        case .records: "See what is saved and its coverage"
        case .about: "Privacy, sources and how airQ works"
        case .erase: "Permanently remove your saved record"
        default: ""
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(AppRoute.moreMenu.actions, id: \.self, content: row)
            }
            Section {
                DisclosureGroup("Data & privacy") {
                    ForEach(AppRoute.moreMenu.privacy, id: \.self, content: row)
                }
                .tint(.primary)
                .frame(minHeight: 44)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AirQStyle.atmosphere }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ route: AppRoute) -> some View {
        let color = route == .erase ? Color.red : AirQStyle.accent
        return NavigationLink(value: route) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: route.systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: iconSize, height: iconSize)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title).font(.body.weight(.semibold))
                    Text(subtitle(route)).font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
        }
    }
}
