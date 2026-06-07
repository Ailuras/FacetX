import FacetXCore
import SwiftUI

/// Multi-tag editor: each tag is a removable colored chip, plus an inline
/// field that commits a new tag on Enter or comma. Reads/writes a single
/// comma-joined string so it slots into the existing `tagsText` state and
/// autosave signature without invasive changes.
struct TagChipEditor: View {
    @Binding var tagsText: String
    let knownColors: AppSettings

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var tags: [String] {
        FacetMetadata.tags(from: tagsText)
    }

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(tags, id: \.self) { tag in
                chip(tag)
            }
            inputField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private func chip(_ tag: String) -> some View {
        let color = knownColors.tagColor(for: tag)
        return HStack(spacing: 3) {
            Text("#")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color.opacity(0.65))
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color.opacity(0.70))
            }
            .buttonStyle(.plain)
            .help("Remove tag")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var inputField: some View {
        HStack(spacing: 2) {
            Text("#")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            TextField(tags.isEmpty ? "Add tag" : "", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .focused($fieldFocused)
                .frame(minWidth: 40)
                .fixedSize()
                .onSubmit { commitDraft() }
                .onChange(of: draft) { _, new in
                    if new.contains(",") || new.contains("\n") {
                        commitDraft()
                    }
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func commitDraft() {
        let parsed = FacetMetadata.tags(from: draft)
        guard !parsed.isEmpty else { draft = ""; return }
        var existing = tags
        for tag in parsed where !existing.contains(where: { $0.lowercased() == tag.lowercased() }) {
            existing.append(tag)
        }
        tagsText = existing.joined(separator: ", ")
        draft = ""
    }

    private func remove(_ tag: String) {
        let remaining = tags.filter { $0.lowercased() != tag.lowercased() }
        tagsText = remaining.joined(separator: ", ")
    }
}
