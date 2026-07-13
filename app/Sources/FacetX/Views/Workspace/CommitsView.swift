import AppKit
import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Outline model

struct HeadingItem: Identifiable, Hashable {
    let id = UUID()
    let level: Int
    let text: String
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
    @State private var documents: [RepositoryDocument] = []
    @State private var selectedDocumentID: RepositoryDocument.ID?
    @State private var editorText = ""
    @State private var savedText = ""
    @State private var statusMessage: String?
    @State private var editing = false
    @State private var isAutosaving = false
    @State private var fileCommits: [LocalGitCommit] = []
    @State private var isLoadingFileCommits = false
    @State private var showingHistoryPopover = false
    @State private var showingAttachmentPopover = false
    @State private var attachmentVersion = 0
    @StateObject private var editorController = MarkdownEditorController()

    @State private var hoveredDocID: String? = nil
    @AppStorage("docFullWidth") private var fullWidth = false

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

    private var selectedDocument: RepositoryDocument? {
        documents.first { $0.id == selectedDocumentID }
    }

    private var hasUnsavedChanges: Bool {
        selectedDocument != nil && editorText != savedText
    }

    private var filteredDocuments: [RepositoryDocument] {
        guard !query.isEmpty else { return documents }
        return documents.filter { $0.title.lowercased().contains(query) }
    }

    private var headings: [HeadingItem] {
        parseHeadings(editorText)
    }

    private var wordCount: Int {
        editorText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var fileSizeString: String {
        let count = editorText.utf8.count
        if count < 1024 { return "\(count) B" }
        return String(format: "%.1f KB", Double(count) / 1024.0)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Doc list & Outline
            VStack(spacing: 0) {
                docSidebar
                    .frame(maxHeight: .infinity)
                
                if !headings.isEmpty {
                    Divider()
                    outlineSidebarSection
                        .frame(height: 200)
                }
            }
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
        .onChange(of: selectedDocumentID) { reloadFileCommits() }
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
                            .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                            .contentShape(Rectangle())
                            .facetHoverSurface(tint: .secondary,
                                               fill: Color.primary.opacity(0.04),
                                               hoverFill: Color.primary.opacity(0.07),
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

    private func docRowCard(_ doc: RepositoryDocument) -> some View {
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

    private var outlineSidebarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.pick("Outline", "文档大纲"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(headings) { heading in
                        HStack(spacing: 4) {
                            Text(String(repeating: "  ", count: heading.level - 1))
                            Text(heading.level == 1 ? "•" : "-")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(heading.level == 1 ? Color.accentColor : .secondary)
                            Text(heading.text)
                                .font(.system(size: 11, weight: heading.level == 1 ? .semibold : .regular))
                                .foregroundStyle(heading.level == 1 ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 4)
            }
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
                "初始化文档以在该仓库中创建专属 of 规划空间。"))
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
                    .frame(maxWidth: fullWidth ? .infinity : 850)
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

    private func docControlBar(_ doc: RepositoryDocument) -> some View {
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

            // File metrics
            HStack(spacing: 8) {
                FacetInfoBadge(text: L10n.pick("\(wordCount) words", "\(wordCount) 字"),
                               systemImage: "text.alignleft",
                               tint: .secondary,
                               fill: Color.primary.opacity(0.04))
                
                // File Size Badge
                FacetInfoBadge(text: fileSizeString,
                               systemImage: "doc.circle",
                               tint: .secondary,
                               fill: Color.primary.opacity(0.04))
            }

            if isAutosaving {
                Text(L10n.pick("Saving...", "正在保存..."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if hasUnsavedChanges {
                Text(L10n.pick("Unsaved", "有未保存更改"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            // Actions - all styled uniformly using PlanView's chip style
            HStack(spacing: 8) {
                Button {
                    showingAttachmentPopover = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary,
                                           fill: Color.primary.opacity(0.04),
                                           hoverFill: Color.primary.opacity(0.07),
                                           hoverStroke: FacetTheme.hairline)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Attach to Work Item", "关联到工作项"))
                .popover(isPresented: $showingAttachmentPopover, arrowEdge: .bottom) {
                    documentAttachmentPopover(doc)
                }

                // Revision History Button (Popover)
                Button {
                    showingHistoryPopover = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary,
                                           fill: Color.primary.opacity(0.04),
                                           hoverFill: Color.primary.opacity(0.07),
                                           hoverStroke: FacetTheme.hairline)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Revision History", "版本历史"))
                .popover(isPresented: $showingHistoryPopover, arrowEdge: .bottom) {
                    fileHistoryPopoverContent
                }

                // Export menu button
                Menu {
                    Button(L10n.pick("Export to Markdown", "导出为 Markdown")) { exportToMarkdown() }
                    Button(L10n.pick("Export to PDF", "导出为 PDF")) { exportToPDF() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary,
                                           fill: Color.primary.opacity(0.04),
                                           hoverFill: Color.primary.opacity(0.07),
                                           hoverStroke: FacetTheme.hairline)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.pick("Export Document", "导出文档"))

                // Reveal in Finder button
                Button {
                    revealSelectedDocument()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary,
                                           fill: Color.primary.opacity(0.04),
                                           hoverFill: Color.primary.opacity(0.07),
                                           hoverStroke: FacetTheme.hairline)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Reveal in Finder", "在 Finder 中显示"))

                // Full width toggle (preview only)
                if !editing {
                    Button {
                        fullWidth.toggle()
                    } label: {
                        Image(systemName: fullWidth ? "arrow.right.and.line.vertical.and.arrow.left" : "arrow.left.and.line.vertical.and.arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                            .contentShape(Rectangle())
                            .facetHoverSurface(tint: .secondary,
                                               fill: Color.primary.opacity(0.04),
                                               hoverFill: Color.primary.opacity(0.07),
                                               hoverStroke: FacetTheme.hairline)
                    }
                    .buttonStyle(.plain)
                    .help(fullWidth ? L10n.pick("Constrain Width", "限制宽度") : L10n.pick("Full Width", "全宽显示"))
                }

                // Edit/Preview Picker
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

    private var fileHistoryPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.pick("Revision History", "版本历史"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            if isLoadingFileCommits {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else if fileCommits.isEmpty {
                Text(L10n.pick("No revisions detected.", "暂无版本修改记录。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(fileCommits.indices, id: \.self) { index in
                            let commit = fileCommits[index]
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.purple.opacity(0.6))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(commit.summary)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    
                                    HStack(spacing: 6) {
                                        Text(commit.shortSHA)
                                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.purple.opacity(0.8))
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(commit.authorName)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(relativeDate(commit.date))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            
                            if index != fileCommits.count - 1 {
                                Divider().padding(.leading, 28)
                            }
                        }
                    }
                }
                .thinScrollIndicators()
                .frame(width: 320, height: 260)
            }
        }
    }

    private func documentAttachmentPopover(_ document: RepositoryDocument) -> some View {
        let workItems = items.filter { $0.facetKind == .task || $0.facetKind == .event }
        return VStack(alignment: .leading, spacing: 0) {
            Text(L10n.pick("Attach to Work Item", "关联到工作项"))
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            if workItems.isEmpty {
                Text(L10n.pick("No tasks or events in this project.", "该项目暂无任务或事件。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(workItems) { item in
                            let paths = item.facetID.map { ItemStore.shared.documentPaths(for: $0) } ?? []
                            let linked = paths.contains(document.relativePath)
                            Button {
                                guard let facetID = item.facetID else { return }
                                var updated = paths
                                if linked { updated.removeAll { $0 == document.relativePath } }
                                else { updated.append(document.relativePath) }
                                ItemStore.shared.setDocumentPaths(updated, for: facetID)
                                attachmentVersion += 1
                                Task { await onItemsChanged() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.kind == .reminder ? "checkmark.circle" : "calendar")
                                        .foregroundStyle(item.kind == .reminder ? .green : .blue)
                                    Text(item.content)
                                        .lineLimit(1)
                                    Spacer()
                                    if linked { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(width: 320, height: min(CGFloat(workItems.count) * 34 + 12, 280))
            }
        }
        .id(attachmentVersion)
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
        let result = (try? RepositoryDocumentStore.list(repositoryPath: repoPath)) ?? []

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
            let currentContent = (try? RepositoryDocumentStore.read(
                repositoryPath: repoPath,
                relativePath: selectedDoc.relativePath
            )) ?? ""
            if currentContent != editorText && !hasUnsavedChanges {
                editorText = currentContent
                savedText = currentContent
            }
        }
    }

    private func selectDocument(_ document: RepositoryDocument) {
        if hasUnsavedChanges { saveSelectedDocument() }
        selectedDocumentID = document.id
        editorText = (try? RepositoryDocumentStore.read(
            repositoryPath: repoPath,
            relativePath: document.relativePath
        )) ?? ""
        savedText = editorText
    }

    private func reloadFileCommits() {
        guard let rootPath = repoPath.flatMap({ ($0 as NSString).expandingTildeInPath }),
              let doc = selectedDocument else {
            fileCommits = []
            return
        }

        let relativePath = doc.relativePath
        isLoadingFileCommits = true
        Task {
            let commits = await LocalGitRepository.gitLogForFile(rootPath: rootPath, filePath: relativePath)
            await MainActor.run {
                self.fileCommits = commits
                self.isLoadingFileCommits = false
            }
        }
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
        do {
            let document = try RepositoryDocumentStore.create(
                repositoryPath: repoPath,
                title: L10n.pick("New Document", "新文档")
            )
            reload()
            if let doc = documents.first(where: { $0.id == document.id }) {
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
                try RepositoryDocumentStore.save(
                    repositoryPath: repoPath,
                    relativePath: selectedDocument.relativePath,
                    body: editorText
                )
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
            try RepositoryDocumentStore.save(
                repositoryPath: repoPath,
                relativePath: selectedDocument.relativePath,
                body: editorText
            )
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

    // MARK: - Exporting

    private func exportToMarkdown() {
        guard let doc = selectedDocument else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        savePanel.nameFieldStringValue = doc.title + ".md"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try editorText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save markdown: \(error)")
                }
            }
        }
    }

    private func exportToPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = (selectedDocument?.title ?? "Document") + ".pdf"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let exporter = NotePDFExporter()
                exporter.export(text: editorText) { result in
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url, options: .atomic)
                        } catch {
                            print("Failed to write PDF: \(error)")
                        }
                    case .failure(let error):
                        print("Failed to export PDF: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func parseHeadings(_ content: String) -> [HeadingItem] {
        let lines = content.components(separatedBy: .newlines)
        return lines.compactMap { line -> HeadingItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return HeadingItem(level: 1, text: String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("## ") {
                return HeadingItem(level: 2, text: String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("### ") {
                return HeadingItem(level: 3, text: String(trimmed.dropFirst(4)))
            }
            return nil
        }
    }
}
