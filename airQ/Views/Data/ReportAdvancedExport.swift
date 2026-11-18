import SwiftUI

struct ReportAdvancedExport: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advanced export").font(.headline)
            NavigationLink(value: AppRoute.export) {
                HStack {
                    Label("Export raw records", systemImage: "archivebox")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
            }
            Text("CSV tables and original provider responses for detailed analysis or a full copy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .airQCard()
    }

}
