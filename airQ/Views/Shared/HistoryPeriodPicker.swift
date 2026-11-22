import SwiftUI
import RespiratoryKit

struct HistoryPeriodPicker: View {
    let title: String
    @Environment(\.historyPeriod) private var period
    @Environment(\.setHistoryPeriod) private var setPeriod
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let picker = Picker(title, selection: Binding(get: { period }, set: { setPeriod($0) })) {
            ForEach(HistoryPeriod.allCases) { Text($0.title).tag($0) }
        }
        if typeSize >= .xxLarge {
            picker.pickerStyle(.menu)
                .controlSize(.large)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}
