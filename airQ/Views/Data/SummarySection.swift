import SwiftUI
import RespiratoryKit

struct SummarySection: View {
    let summary: ClinicianSummary

    var body: some View {
        DisclosureGroup("Full plain-text summary") {
            VStack(alignment: .leading, spacing: 12) {
                ShareLink("Share as text", item: summary.text, subject: Text("airQ summary"))
                Text(summary.text).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        }
        .airQCard()
    }
}
