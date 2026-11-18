import SwiftUI

struct MoreView: View {
    private let headings = ["Record a little more", "Preferences", "Your data", ""]
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
            ForEach(Array(AppRoute.menuSections.enumerated()), id: \.offset) { index, section in
                Section {
                    ForEach(section, id: \.self) { route in
                        NavigationLink(value: route) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: route.systemImage).font(.title3)
                                    .foregroundStyle(route == .erase ? Color.red : AirQStyle.accent)
                                    .frame(width: 26).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.title).font(.body.weight(.medium))
                                    Text(subtitle(route)).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                } header: { Text(headings[index]) }
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
    }
}
