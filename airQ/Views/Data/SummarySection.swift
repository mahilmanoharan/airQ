import SwiftUI
import RespiratoryKit

/// A readable preview of the exact plain text shared and included in an export.
/// Paragraph breaks provide layout only; the summary owns every count and denominator.
struct SummarySection: View {
    let summary: ClinicianSummary

    private var paragraphs: [String] {
        // The opening line is the report's dates, already shown in ReportOverview.
        Array(summary.text.components(separatedBy: "\n\n").dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary to share")
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                SummaryParagraph(text: paragraph)
            }
            DisclosureGroup("Full plain-text summary") {
                Text(summary.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .airQCard()
        }
    }
}

private struct SummaryParagraph: View {
    let text: String

    private var lines: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading = lines.first {
                Text(heading)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            if lines.count > 1 {
                Text(lines.dropFirst().joined(separator: "\n"))
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .airQCard()
    }
}
