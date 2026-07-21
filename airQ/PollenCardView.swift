import SwiftUI
import AirQualityKit

struct PollenCardView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("\(count)")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(PollenPresentation.color(for: count))

            Text("Pollen")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(PollenPresentation.category(for: count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PollenPresentation.color(for: count).opacity(0.1))
        )
    }
}

#Preview {
    PollenCardView(count: 30)
}
