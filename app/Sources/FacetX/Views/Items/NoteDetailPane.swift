import FacetXCore
import SwiftUI

/// Detail pane for a note: metadata on top, markdown below. Defaults to a
/// rendered preview; an Edit toggle swaps in a plain editor that writes back to
/// the project's local `.md` file. Live-rendering and shortcuts are layered on
/// in a later pass.
struct NoteDetailPane: View {
    let item: ProjectItem
    let project: Project
    let onClose: () -> Void

    @State private var text: String = ""
    @State private var loaded = false
    @State private var editing = false

    private var dataDirectory: String { project.dataDirectory ?? "" }
    private var facetID: String? { item.facetID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataHeader
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
        .onChange(of: item.id) { _, _ in
            loaded = false
            editing = false
            load()
        }
        .onDisappear(perform: persist)
    }

    // ── Metadata ──────────────────────────────────────────────────────────────

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.content)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(3)

            HStack(spacing: 8) {
                Label(item.facetKind.singularTitle, systemImage: item.facetKind.systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.facetKind.color)
                if let date = item.date {
                    Label(dateLabel(date), systemImage: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if !item.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // ── Body ────────────────────────────────────────────────────────────────

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $editing) {
                    Text(L10n.pick("Preview", "预览")).tag(false)
                    Text(L10n.pick("Edit", "编辑")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if editing {
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .onChange(of: text) { _, _ in persist() }
            } else {
                ScrollView {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.pick("Empty note. Switch to Edit to start writing.",
                                       "空笔记。切换到编辑开始书写。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    } else {
                        MarkdownPreview(text: text)
                            .padding(16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private func load() {
        guard !loaded, let facetID, !dataDirectory.isEmpty else { return }
        text = NoteStore.shared.body(dataDirectory: dataDirectory, facetID: facetID)
        loaded = true
    }

    private func persist() {
        guard loaded, let facetID, !dataDirectory.isEmpty else { return }
        NoteStore.shared.save(dataDirectory: dataDirectory, facetID: facetID, body: text)
    }

    private func dateLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = item.isAllDay ? .none : .short
        return fmt.string(from: date)
    }
}
