import FacetXCore
import MarkdownUI
import SwiftUI

/// Detail pane for a note: metadata on top; below, a live-highlighted markdown
/// editor with an optional fully-rendered preview (swift-markdown-ui) to its
/// right. The editor writes back to the project's local `.md` file.
struct NoteDetailPane: View {
    let item: ProjectItem
    let project: Project
    let onClose: () -> Void

    @State private var text: String = ""
    @State private var loaded = false
    @AppStorage("noteShowPreview") private var showPreview = true
    @StateObject private var editorController = MarkdownEditorController()

    private var dataDirectory: String { project.effectiveDataDirectory }
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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                formattingToolbar
                Divider()
                // Live-highlighted source editor.
                MarkdownEditor(text: $text, controller: editorController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: text) { _, _ in persist() }
            }
            .frame(maxWidth: .infinity)

            if showPreview {
                Divider()
                // Fully rendered preview (swift-markdown-ui).
                ScrollView {
                    Markdown(text)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .background(FacetTheme.quietPanel.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            toolbarButton("bold", help: "Bold ⌘B") { editorController.bold() }
            toolbarButton("italic", help: "Italic ⌘I") { editorController.italic() }
            toolbarButton("chevron.left.forwardslash.chevron.right", help: L10n.pick("Code", "代码")) { editorController.code() }
            Divider().frame(height: 14)
            toolbarButton("number", help: L10n.pick("Heading", "标题")) { editorController.heading() }
            toolbarButton("list.bullet", help: L10n.pick("List", "列表")) { editorController.bulletList() }
            toolbarButton("text.quote", help: L10n.pick("Quote", "引用")) { editorController.quote() }
            toolbarButton("link", help: "Link ⌘K") { editorController.link() }
            Spacer()
            toolbarButton(showPreview ? "sidebar.right" : "sidebar.squares.right",
                          help: showPreview ? L10n.pick("Hide preview", "隐藏预览")
                                            : L10n.pick("Show preview", "显示预览")) {
                showPreview.toggle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func toolbarButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
