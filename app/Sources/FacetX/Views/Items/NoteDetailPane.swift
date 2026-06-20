import FacetXCore
import SwiftUI

/// Detail pane for a note: metadata on top; below, a single WYSIWYG markdown
/// editor (Milkdown + KaTeX in a WKWebView) that reads and writes the project's
/// local `.md` file. Markdown remains the source of truth.
struct NoteDetailPane: View {
    let item: ProjectItem
    let project: Project
    let onClose: () -> Void

    @State private var text: String = ""
    @State private var loaded = false

    private var dataDirectory: String { project.effectiveDataDirectory }
    private var facetID: String? { item.facetID }
    private var documentID: String { facetID ?? item.id }

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
        MilkdownNoteEditor(text: $text, documentID: documentID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: text) { _, _ in persist() }
            .opacity(loaded ? 1 : 0)
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
