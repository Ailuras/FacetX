import SwiftUI

/// A multi-select filter row (Fields / Tier). Shows a colored dot (the color
/// lives on the dot, not the text), the label, and a checkmark when selected.
/// Tapping toggles selection; right-click sets the color, persisted in the
/// metadata tables under `colorKey`.
struct FilterRow: View {
    let title: String
    let colorKey: String
    let defaultColor: LabelColor
    let isSelected: Bool
    let onToggle: () -> Void

    private var metadata: MetadataStore = .shared

    init(title: String, colorKey: String, defaultColor: LabelColor, isSelected: Bool, onToggle: @escaping () -> Void) {
        self.title = title
        self.colorKey = colorKey
        self.defaultColor = defaultColor
        self.isSelected = isSelected
        self.onToggle = onToggle
    }

    private var color: Color {
        metadata.color(forKey: colorKey, default: defaultColor)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Color") {
                ForEach(LabelColor.allCases) { c in
                    Button(c.title) { metadata.setLabelColor(key: colorKey, colorName: c.rawValue) }
                }
                Divider()
                Button("Default") { metadata.setLabelColor(key: colorKey, colorName: nil) }
            }
        }
    }
}
