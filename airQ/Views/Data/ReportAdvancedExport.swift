import SwiftUI

struct ReportAdvancedExport: View {
    var body: some View {
        DisclosureGroup {
            NavigationLink(value: AppRoute.export) {
                HStack {
                    Label("Export raw records", systemImage: "archivebox")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
            .tint(AirQStyle.accent)
        } label: {
            Text("Advanced export")
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(.primary)
        .airQCard()
    }
}
