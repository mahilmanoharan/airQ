import SwiftUI

struct ReportPreview<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20, content: content)
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .background(AirQStyle.page)
            .navigationTitle("Report preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
