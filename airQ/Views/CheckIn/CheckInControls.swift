import SwiftUI

/// A check-in row with a full-width tap target and a check mark for the selected answer.
struct AnswerButton: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail { Text(detail).font(.subheadline).opacity(0.8) }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(AirQStyle.accent).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(AirQStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SymptomChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true) }
                Text(title).font(.body)
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(AirQStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isSelected ? AirQStyle.accent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wraps children onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An infinite or missing proposal means "as wide as you need": never report an infinite size.
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let rows = arrange(width: available ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: available ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(Self.proposal(forRowWidth: bounds.width))
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private static func proposal(forRowWidth width: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            // A chip wider than the row is asked to fit it (its text wraps) instead of overflowing.
            let size = subviews[index].sizeThatFits(Self.proposal(forRowWidth: width))
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

struct PeakFlowField: View {
    let value: Int?
    let set: (Int?) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent("Peak flow (optional)") {
            TextField("L/min", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(maxWidth: 100)
        }
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: value) { _, new in if !isFocused { text = new.map(String.init) ?? "" } }
        .onChange(of: text) { _, new in set(Int(new.filter(\.isNumber))) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
    }
}
