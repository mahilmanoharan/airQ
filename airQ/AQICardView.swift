import SwiftUI
import AirQualityKit

struct AQICardView: View {
    let aqi: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("\(aqi)")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(AirQualityPresentation.color(for: aqi))

            Text("AQI")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(AirQualityPresentation.category(for: aqi))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AirQualityPresentation.color(for: aqi).opacity(0.1))
        )
    }
}

#Preview {
    AQICardView(aqi: 42)
}
