import SwiftUI

struct AnalysisCardView: View {
    let title: String
    let message: String
    let tintColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tintColor.opacity(0.1))
        )
    }
}

#Preview {
    AnalysisCardView(
        title: "AQI analysis",
        message: "Air quality is satisfactory, and air pollution poses little or no risk.",
        tintColor: .green
    )
}
