import SwiftUI
import AirQualityKit

struct PollenCardView: View {
    let index: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(PollenPresentation.color(for: index))

            Text("Pollen")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(PollenPresentation.category(for: index))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PollenPresentation.color(for: index).opacity(0.1))
        )
    }
}

#Preview {
    PollenCardView(index: 3)
}
