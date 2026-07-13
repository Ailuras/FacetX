import AppKit
import FacetXCore
import SwiftUI

// MARK: - Document model

private struct FacetXRepoDocument: Identifiable, Equatable {
    let url: URL
    let modifiedAt: Date?
    let isReadme: Bool

    var id: String { url.path }

    var title: String {
        if isReadme { return "README" }
        return url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Main view

/// Project Documents Workspace: reads repo-root README.md and all markdown documents
/// in the `.facetx` folder. Renders markdown with rich web preview (read-only) and
/// provides a native markdown editor with formatting shortcuts.
struct CommitsView: View {
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let items: [ProjectItem]
    let searchText: String
    let refreshTrigger: Int
    let showTodayPanel: Binding<Bool>
    let showAssistantPanel: Binding<Bool>
    let todayFullscreen: Binding<Bool>
    let assistantFullscreen: Binding<Bool>
    let onItemsChanged: () async -> Void

    // ── Document list & selection ─────────────────────────────────────────────
    @State private var documents: [FacetXRepoDocument] = []
    @State private var selectedDocumentID: FacetXRepoDocument.ID?
    @State private var editorText = ""
    @State private var savedText = ""
    @State private var statusMessage: String?
    @State private var editing = false
    @State private var isAutosaving = false
    @StateObject private var editorController = MarkdownEditorController()

    @State private var hoveredDocID: String? = nil

    // ── Derived ───────────────────────────────────────────────────────────────

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var repoPath: String? {
        guard let path = project.githubLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }

    private var repoURL: URL? {
        repoPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    private var docsURL: URL? {
        repoURL?.appendingPathComponent(".facetx", isDirectory: true)
    }

    private var selectedDocument: FacetXRepoDocument? {
        documents.first { $0.id == selectedDocumentID }
    }

    private var hasUnsavedChanges: Bool {
        selectedDocument != nil && editorText != savedText
    }

    private var filteredDocuments: [FacetXRepoDocument] {
        guard !query.isEmpty else { return documents }
        return documents.filter { $0.title.lowercased().contains(query) }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Doc list
            docSidebar
                .frame(width: 260)
                .background(FacetTheme.quietPanel)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(FacetTheme.hairline).frame(width: 1)
                }

            // Right main: Markdown render / editor
            mainDocumentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FacetTheme.canvas)
        .onAppear { reload() }
        .onChange(of: project.id) { reload() }
        .onChange(of: project.githubLocalPath) { reload() }
        .onChange(of: refreshTrigger) { reload() }
        .onChange(of: searchText) {
            if let selectedDocumentID,
               !filteredDocuments.contains(where: { $0.id == selectedDocumentID }) {
                self.selectedDocumentID = nil
            }
        }
    }

    // MARK: - Sidebar

    private var docSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text(L10n.pick("Project Docs", "项目文档"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Text("\(filteredDocuments.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                if repoURL != nil {
                    Button {
                        createDocument()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .facetHoverSurface(tint: .secondary, fill: .clear,
                                               hoverFill: Color.primary.opacity(0.055),
                                               hoverStroke: FacetTheme.hairline)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.pick("New Document", "新建文档"))
                    .disabled(docsURL == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if repoURL == nil {
                noRepoState
            } else if documents.isEmpty {
                emptyDocsState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredDocuments) { doc in
                            Button {
                                selectDocument(doc)
                            } label: {
                                docRowCard(doc)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .thinScrollIndicators()
            }
        }
    }

    private func docRowCard(_ doc: FacetXRepoDocument) -> some View {
        let isSelected = selectedDocumentID == doc.id
        let isHovered = hoveredDocID == doc.id

        return HStack(spacing: 10) {
            Image(systemName: doc.isReadme ? "doc.richtext" : "doc.text")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(doc.isReadme ? Color.orange : Color.accentColor)
                .frame(width: 24, height: 24)
                .background((doc.isReadme ? Color.orange : Color.accentColor).opacity(isSelected ? 0.20 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)

                if let modified = doc.modifiedAt {
                    Text(relativeDate(modified))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if doc.isReadme {
                Text("README")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? FacetTheme.softAccent : (isHovered ? Color.primary.opacity(0.04) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? FacetTheme.hairline : .clear), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredDocID = hovering ? doc.id : nil
        }
    }

    private var noRepoState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(L10n.pick("No Repository Bound", "未绑定仓库"))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.pick(
                "Please configure a local Git repository path in project settings.",
                "请在项目编辑中选择一个本地 Git 仓库路径。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyDocsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(L10n.pick("No Documents Yet", "暂无规划文档"))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.pick(
                "Initialize the docs area to create a project-specific workspace folder inside this repository.",
                "初始化文档以在该仓库中创建专属的规划空间。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                initializeDocs()
            } label: {
                Label(L10n.pick("Initialize Docs", "初始化文档"), systemImage: "folder.badge.plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Main Area

    @ViewBuilder private var mainDocumentArea: some View {
        if let doc = selectedDocument {
            VStack(spacing: 0) {
                // Top control bar
                docControlBar(doc)

                Divider()

                // Centered sheet layout for readability
                HStack(spacing: 0) {
                    Spacer(minLength: 16)

                    VStack(alignment: .leading, spacing: 0) {
                        if editing {
                            formattingToolbar
                            Divider()
                            MarkdownEditor(text: $editorText, controller: editorController)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onChange(of: editorText) { _, newText in
                                    autosave(newText)
                                }
                        } else {
                            if editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(L10n.pick("Empty document. Switch to Edit to write.",
                                               "空文档。请切换至编辑模式书写。"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            } else {
                                MarkdownPreviewWeb(text: editorText, fullWidth: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .id(doc.id + "-\(editorText.hashValue)")
                            }
                        }
                    }
                    .background(FacetTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: 850)
                    .padding(.vertical, 16)

                    Spacer(minLength: 16)
                }
                .background(FacetTheme.canvas)
            }
        } else {
            ContentUnavailableView(
                L10n.pick("Select a Document", "选择一个文档"),
                systemImage: "doc.text",
                description: Text(L10n.pick("Choose README or create a document to get started.",
                                            "选择根目录 README 或新建一个文档以开始。"))
            )
        }
    }

    private func docControlBar(_ doc: FacetXRepoDocument) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text(doc.url.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAutosaving {
                Text(L10n.pick("Saving...", "正在保存..."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if hasUnsavedChanges {
                Text(L10n.pick("Unsaved", "有未保存更改"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            // Actions
            HStack(spacing: 4) {
                Button {
                    saveSelectedDocument()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary, fill: .clear,
                                           hoverFill: Color.primary.opacity(0.055),
                                           hoverStroke: FacetTheme.hairline)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Save Document", "保存文档"))
                .disabled(!hasUnsavedChanges)

                Button {
                    revealSelectedDocument()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary, fill: .clear,
                                           hoverFill: Color.primary.opacity(0.055),
                                           hoverStroke: FacetTheme.hairline)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Reveal in Finder", "在 Finder 中显示"))

                Picker("", selection: $editing) {
                    Text(L10n.pick("Preview", "预览")).tag(false)
                    Text(L10n.pick("Edit", "编辑")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(FacetTheme.quietPanel.opacity(0.5))
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

    // MARK: - Actions & Loading

    private func reload() {
        var result: [FacetXRepoDocument] = []

        // 1. README.md
        if let repoURL {
            let readmeURL = repoURL.appendingPathComponent("README.md")
            if FileManager.default.fileExists(atPath: readmeURL.path) {
                let values = try? readmeURL.resourceValues(forKeys: [.contentModificationDateKey])
                result.append(FacetXRepoDocument(
                    url: readmeURL,
                    modifiedAt: values?.contentModificationDate,
                    isReadme: true
                ))
            }
        }

        // 2. .facetx documents
        if let docsURL,
           let urls = try? FileManager.default.contentsOfDirectory(
               at: docsURL,
               includingPropertiesForKeys: [.contentModificationDateKey],
               options: [.skipsHiddenFiles]) {
            let facetxDocs = urls
                .filter { $0.pathExtension.lowercased() == "md" }
                .map { url -> FacetXRepoDocument in
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    return FacetXRepoDocument(url: url,
                                              modifiedAt: values?.contentModificationDate,
                                              isReadme: false)
                }
                .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
            result.append(contentsOf: facetxDocs)
        }

        self.documents = result

        // Selection auto-routing
        if selectedDocumentID == nil {
            if let firstDoc = result.first {
                selectDocument(firstDoc)
            }
        } else if let id = selectedDocumentID, !result.contains(where: { $0.id == id }) {
            if let firstDoc = result.first {
                selectDocument(firstDoc)
            } else {
                selectedDocumentID = nil
                editorText = ""
                savedText = ""
            }
        } else if let selectedDoc = result.first(where: { $0.id == selectedDocumentID }) {
            // Re-read file content if it changed on disk
            let currentContent = (try? String(contentsOf: selectedDoc.url, encoding: .utf8)) ?? ""
            if currentContent != editorText && !hasUnsavedChanges {
                editorText = currentContent
                savedText = currentContent
            }
        }
    }

    private func selectDocument(_ document: FacetXRepoDocument) {
        if hasUnsavedChanges { saveSelectedDocument() }
        selectedDocumentID = document.id
        editorText = (try? String(contentsOf: document.url, encoding: .utf8)) ?? ""
        savedText = editorText
    }

    private func initializeDocs() {
        guard let docsURL else { return }
        do {
            try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            reload()
        } catch {
            statusMessage = L10n.pick("Could not initialize .facetx", "无法初始化 .facetx")
        }
    }

    private func createDocument() {
        guard let docsURL else { return }
        do {
            try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            let url = uniqueDocumentURL(in: docsURL)
            let title = url.deletingPathExtension().lastPathComponent
            try "# \(title.capitalized)\n\n".write(to: url, atomically: true, encoding: .utf8)
            reload()
            if let doc = documents.first(where: { $0.url == url }) {
                selectDocument(doc)
            }
        } catch {
            statusMessage = L10n.pick("Could not create document", "无法创建文档")
        }
    }

    private func autosave(_ text: String) {
        guard let selectedDocument else { return }
        isAutosaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Only save if the text hasn't changed since this autosave was triggered
            guard editorText == text else { return }
            do {
                try editorText.write(to: selectedDocument.url, atomically: true, encoding: .utf8)
                savedText = editorText
                isAutosaving = false
            } catch {
                isAutosaving = false
            }
        }
    }

    private func saveSelectedDocument() {
        guard let selectedDocument else { return }
        do {
            try editorText.write(to: selectedDocument.url, atomically: true, encoding: .utf8)
            savedText = editorText
            reload()
        } catch {
            statusMessage = L10n.pick("Could not save document", "无法保存文档")
        }
    }

    private func revealDocsFolder() {
        guard let docsURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([docsURL])
    }

    private func revealSelectedDocument() {
        guard let selectedDocument else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedDocument.url])
    }

    private func uniqueDocumentURL(in directory: URL) -> URL {
        var index = 1
        while true {
            let filename = index == 1 ? "new-doc.md" : "new-doc-\(index).md"
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
