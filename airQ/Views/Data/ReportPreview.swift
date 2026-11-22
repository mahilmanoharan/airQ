import SwiftUI

struct ReportPreview<Content: View>: View {
    @Binding var isPresented: Bool
    let pdf: ReportPDF?
    @ViewBuilder let content: () -> Content
    @State private var showsPrintLayout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if pdf != nil {
                        Button {
                            showsPrintLayout = true
                        } label: {
                            Label("View print layout", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    content()
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(AirQStyle.page)
            .navigationTitle("Report preview")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsPrintLayout) {
                if let pdf { ReportPrintLayout(pdf: pdf) }
            }
            .onChange(of: pdf) { showsPrintLayout = false }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
