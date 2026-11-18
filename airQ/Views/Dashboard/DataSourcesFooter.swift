import SwiftUI
import AirQualityKit

/// Credits every source behind the dashboard. WAQI's per-station attributions (the originating
/// agency and the WAQI project) come with each reading and are linked when WAQI gives a URL.
struct DataSourcesFooter: View {
    let attributions: [DataAttribution]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Data sources").font(.caption.weight(.semibold))
            if attributions.isEmpty {
                Text("Air quality: World Air Quality Index Project")
            } else {
                Text("Air quality:")
                ForEach(attributions) { credit in
                    if let url = credit.url {
                        Link(credit.name, destination: url)
                    } else {
                        Text(credit.name)
                    }
                }
            }
            Text("Pollen and hourly history: Google (Pollen and Air Quality APIs)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
