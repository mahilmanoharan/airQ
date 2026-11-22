import CoreTransferable
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct ReportPDF: Equatable, Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

struct ReportPrintLayout: View {
    let pdf: ReportPDF

    var body: some View {
        Group {
            if let document = PDFDocument(data: pdf.data), document.pageCount > 0 {
                PDFPageView(document: document)
                    .id(pdf.data)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: pdf, subject: Text("airQ Respiratory Report"),
                                      preview: SharePreview("airQ Respiratory Report")) {
                                Label("Share report", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
            } else {
                ContentUnavailableView("Couldn’t open the print layout", systemImage: "doc")
            }
        }
        .navigationTitle("Print layout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PDFPageView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.backgroundColor = .secondarySystemBackground
        view.document = document
        view.autoScales = true
        return view
    }

    // The parent replaces this view when the PDF changes, so SwiftUI updates preserve the user's zoom.
    func updateUIView(_ view: PDFView, context: Context) {}
}
