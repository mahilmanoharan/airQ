import SwiftUI

struct ReportAdvancedExport: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advanced export")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            NavigationLink(value: AppRoute.export) {
                HStack {
                    Label("Export raw records", systemImage: "archivebox")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
        }
        .airQCard()
    }
}
