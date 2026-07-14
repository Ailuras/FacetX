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

private struct DocumentNameSheet: View {
    @State private var title: String
    let isRenaming: Bool
    let onCancel: () -> Void
    let onSave: (String) -> Void
    @FocusState private var titleFocused: Bool

    init(title: String,
         isRenaming: Bool,
         onCancel: @escaping () -> Void,
         onSave: @escaping (String) -> Void) {
        _title = State(initialValue: title)
        self.isRenaming = isRenaming
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isRenaming ? "pencil.line" : "doc.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRenaming
                         ? L10n.pick("Rename Note", "重命名笔记")
                         : L10n.pick("New Note", "新建笔记"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.pick("Stored as Markdown in .facetx", "以 Markdown 格式存储在 .facetx 中"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            TextField(L10n.pick("Note title", "笔记标题"), text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit { save() }

            HStack {
                Spacer()
                Button(L10n.t(.cancel), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isRenaming ? L10n.pick("Rename", "重命名") : L10n.pick("Create", "创建")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { titleFocused = true }
    }

    private func save() {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSave(value)
    }
}

private enum NoteEditorMode: String, CaseIterable, Identifiable {
    case read
    case write
    case split

    var id: String { rawValue }
}

private enum NoteInspectorTab: String, CaseIterable, Identifiable {
    case outline
    case history

    var id: String { rawValue }
}

private enum DocumentNamingAction: Identifiable {
    case create
    case rename(RepositoryDocument)

    var id: String {
        switch self {
        case .create: return "create"
        case .rename(let document): return "rename-\(document.id)"
        }
    }
}

// MARK: - Main view

/// Project Documents Workspace: reads repo-root README.md and all markdown documents
/// in the `.facetx` folder. Renders markdown with rich web preview (read-only) and
/// provides a native markdown editor with formatting shortcuts.
struct NotesView: View {
    let project: Project
    let items: [ProjectItem]
    let searchText: String
    let refreshTrigger: Int
    let onItemsChanged: () async -> Void

    // ── Document list & selection ─────────────────────────────────────────────
    @State private var documents: [RepositoryDocument] = []
    @State private var documentContentIndex: [String: String] = [:]
    @State private var selectedDocumentID: RepositoryDocument.ID?
    @State private var editorText = ""
    @State private var savedText = ""
    @State private var statusMessage: String?
    @State private var editorMode: NoteEditorMode = .read
    @State private var isAutosaving = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var fileCommits: [LocalGitCommit] = []
    @State private var isLoadingFileCommits = false
    @State private var inspectorTab: NoteInspectorTab = .outline
    @State private var selectedRevisionID: String?
    @State private var revisionText: String?
    @State private var revisionError: String?
    @State private var isLoadingRevision = false
    @State private var revisionLoadGeneration = 0
    @State private var showingAttachmentPopover = false
    @State private var attachmentVersion = 0
    @State private var namingAction: DocumentNamingAction?
    @State private var documentToDelete: RepositoryDocument?
    @StateObject private var editorController = MarkdownEditorController()

    @State private var hoveredDocID: String? = nil
    @AppStorage("docFullWidth") private var fullWidth = false
    @AppStorage("notesNavigatorVisible") private var navigatorVisible = true
    @AppStorage("notesInspectorVisible") private var inspectorVisible = true

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

    private var selectedRevision: LocalGitCommit? {
        fileCommits.first { $0.id == selectedRevisionID }
    }

    private var isViewingRevision: Bool {
        selectedRevisionID != nil
    }

    private var filteredDocuments: [RepositoryDocument] {
        guard !query.isEmpty else { return documents }
        return documents.filter {
            $0.title.lowercased().contains(query)
                || $0.relativePath.lowercased().contains(query)
                || documentContentIndex[$0.id]?.lowercased().contains(query) == true
        }
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

    private var lineCount: Int {
        max(editorText.components(separatedBy: .newlines).count, 1)
    }

    private var linkedWorkItems: [ProjectItem] {
        guard let path = selectedDocument?.relativePath else { return [] }
        return items.filter { item in
            item.facetID.map { ItemStore.shared.documentPaths(for: $0).contains(path) } ?? false
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            if navigatorVisible {
                docSidebar
                    .frame(maxHeight: .infinity)
                    .frame(width: 248)
                    .background(FacetTheme.quietPanel)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(FacetTheme.hairline).frame(width: 1)
                    }
            }

            mainDocumentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inspectorVisible {
                noteDetailSidebar
            }
        }
        .background(FacetTheme.canvas)
        .animation(FacetTheme.detailSpring, value: inspectorVisible)
        .sheet(item: $namingAction) { action in
            DocumentNameSheet(
                title: {
                    switch action {
                    case .create: return ""
                    case .rename(let document): return document.title
                    }
                }(),
                isRenaming: {
                    if case .rename = action { return true }
                    return false
                }(),
                onCancel: { namingAction = nil },
                onSave: { title in completeNaming(action, title: title) }
            )
        }
        .alert(L10n.pick("Delete note?", "删除笔记？"), isPresented: .init(
            get: { documentToDelete != nil },
            set: { if !$0 { documentToDelete = nil } }
        )) {
            Button(L10n.t(.cancel), role: .cancel) { documentToDelete = nil }
            Button(L10n.t(.delete), role: .destructive) { deleteSelectedDocument() }
        } message: {
            Text(documentToDelete?.title ?? "")
        }
        .onAppear { reload() }
        .onDisappear {
            autosaveTask?.cancel()
            if hasUnsavedChanges { saveSelectedDocument() }
        }
        .onChange(of: project.id) { reload() }
        .onChange(of: project.githubLocalPath) { reload() }
        .onChange(of: refreshTrigger) { reload() }
        .onChange(of: selectedDocumentID) {
            clearRevision()
            reloadFileCommits()
        }
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
                Text(L10n.pick("Notes", "笔记"))
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
                        namingAction = .create
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
                    .help(L10n.pick("New Note", "新建笔记"))
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
                            .contextMenu {
                                Button(L10n.pick("Reveal in Finder", "在 Finder 中显示")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([doc.url])
                                }
                                if !doc.isReadme {
                                    Button(L10n.pick("Rename", "重命名")) {
                                        namingAction = .rename(doc)
                                    }
                                    Divider()
                                    Button(L10n.t(.delete), role: .destructive) {
                                        documentToDelete = doc
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .thinScrollIndicators()
            }

            Divider()
            HStack {
                Label(".facetx", systemImage: "folder")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { revealDocsFolder() } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Reveal Notes Folder", "显示笔记目录"))
                .disabled(docsURL == nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
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

    private var noteDetailSidebar: some View {
        FacetSidebarPane(
            title: L10n.pick("Note Details", "笔记详情"),
            systemImage: "doc.text",
            closeHelp: L10n.pick("Hide Note Details", "隐藏笔记详情"),
            onClose: {
                withAnimation(FacetTheme.detailSpring) { inspectorVisible = false }
            },
            accessory: {
                Picker("", selection: $inspectorTab) {
                    Text(L10n.pick("Outline", "大纲")).tag(NoteInspectorTab.outline)
                    Text(L10n.pick("History", "历史")).tag(NoteInspectorTab.history)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .frame(width: 108)
            }
        ) {
            if inspectorTab == .outline {
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                inspectorSection(L10n.pick("Outline", "文档大纲"), systemImage: "list.bullet.indent") {
                    if headings.isEmpty {
                        Text(L10n.pick("Add headings to build an outline.", "添加标题以生成大纲。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(headings) { heading in
                                Button {
                                    clearRevision()
                                    if editorMode == .read { editorMode = .write }
                                    DispatchQueue.main.async {
                                        editorController.reveal(heading: heading.text)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(heading.level == 1 ? Color.accentColor : Color.secondary.opacity(0.45))
                                            .frame(width: heading.level == 1 ? 5 : 3, height: heading.level == 1 ? 5 : 3)
                                        Text(heading.text)
                                            .font(.system(size: 10.5, weight: heading.level == 1 ? .semibold : .regular))
                                            .foregroundStyle(heading.level == 1 ? .primary : .secondary)
                                            .lineLimit(2)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 10)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                inspectorSection(L10n.pick("Linked Work Items", "关联工作项"), systemImage: "link") {
                    if linkedWorkItems.isEmpty {
                        Text(L10n.pick("This note is not attached yet.", "这篇笔记尚未关联工作项。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(linkedWorkItems) { item in
                                Button {
                                    NotificationCenter.default.post(
                                        name: .selectItemInProjectDetail,
                                        object: nil,
                                        userInfo: ["itemID": item.id]
                                    )
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: item.kind.systemImage)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(item.kind.color)
                                        Text(item.content)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .lineLimit(2)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.035))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                inspectorSection(L10n.pick("Document", "文档"), systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorMetadata(L10n.pick("Words", "字数"), value: "\(wordCount)")
                        inspectorMetadata(L10n.pick("Lines", "行数"), value: "\(lineCount)")
                        inspectorMetadata(L10n.pick("Size", "大小"), value: fileSizeString)
                        if let modified = selectedDocument?.modifiedAt {
                            inspectorMetadata(L10n.pick("Modified", "修改"), value: relativeDate(modified))
                        }
                    }
                }
                }
                .padding(16)
                }
                .thinScrollIndicators()
                .id(attachmentVersion)
            } else {
                revisionHistoryInspector
            }
        }
    }

    private var revisionHistoryInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    clearRevision()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.pick("Current working copy", "当前工作版本"))
                                .font(.system(size: 11, weight: .semibold))
                            Text(hasUnsavedChanges ? L10n.pick("Unsaved changes", "包含未保存修改")
                                                   : L10n.pick("Latest on disk", "磁盘中的最新内容"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if selectedRevisionID == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(10)
                    .background(selectedRevisionID == nil ? FacetTheme.softAccent : Color.primary.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Text(L10n.pick("Committed revisions", "已提交版本"))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isLoadingFileCommits { ProgressView().controlSize(.mini) }
                    Text("\(fileCommits.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 3)
                .padding(.top, 8)

                if !isLoadingFileCommits && fileCommits.isEmpty {
                    ContentUnavailableView(
                        L10n.pick("No Revisions", "暂无历史版本"),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(L10n.pick("Commit this document to begin its history.",
                                                    "提交这篇文档后即可形成版本历史。"))
                    )
                    .frame(minHeight: 180)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(fileCommits) { commit in
                            revisionRow(commit)
                        }
                    }
                }
            }
            .padding(12)
        }
        .thinScrollIndicators()
    }

    private func revisionRow(_ commit: LocalGitCommit) -> some View {
        let selected = selectedRevisionID == commit.id
        return Button {
            loadRevision(commit)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 2) {
                    Circle()
                        .fill(selected ? Color.accentColor : Color.purple.opacity(0.55))
                        .frame(width: 7, height: 7)
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 32)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.summary)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text(commit.shortSHA)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.purple)
                        Text("·")
                        Text(relativeDate(commit.date))
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    Text(commit.authorName)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(9)
            .background(selected ? FacetTheme.softAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func inspectorSection<Content: View>(_ title: String,
                                                 systemImage: String,
                                                 @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorMetadata(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
        .font(.system(size: 10.5))
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
            Text(L10n.pick("No Notes Yet", "暂无笔记"))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.pick(
                "Initialize the notes area inside this repository.",
                "在该仓库中初始化笔记空间。"))
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
                docControlBar(doc)

                if isViewingRevision {
                    revisionWorkspace(doc)
                } else {
                    if editorMode != .read {
                        formattingToolbar
                        Divider()
                    }

                    Group {
                        switch editorMode {
                        case .read:
                            centeredPreview(doc)
                        case .write:
                            centeredEditor
                        case .split:
                            HSplitView {
                                labeledPane(L10n.pick("Markdown", "Markdown"), systemImage: "chevron.left.forwardslash.chevron.right") {
                                    editorPane
                                }
                                labeledPane(L10n.pick("Preview", "预览"), systemImage: "eye") {
                                    previewPane(doc)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    documentStatusBar(doc)
                }
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

    private func revisionWorkspace(_ doc: RepositoryDocument) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedRevision?.summary ?? L10n.pick("Historical revision", "历史版本"))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if let revision = selectedRevision {
                        Text("\(revision.shortSHA) · \(revision.authorName) · \(relativeDate(revision.date))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Label(L10n.pick("Read only", "只读"), systemImage: "lock.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    clearRevision()
                } label: {
                    Label(L10n.pick("Back to Current", "返回当前版本"), systemImage: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Color.purple.opacity(0.055))

            Divider()

            if isLoadingRevision {
                ProgressView(L10n.pick("Loading revision…", "正在加载历史版本…"))
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let revisionText {
                HStack(spacing: 0) {
                    Spacer(minLength: 18)
                    MarkdownPreviewWeb(text: revisionText, fullWidth: true)
                        .background(FacetTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.025), radius: 10, x: 0, y: 4)
                        .frame(maxWidth: fullWidth ? .infinity : 900)
                        .padding(.vertical, 18)
                    Spacer(minLength: 18)
                }
                .background(FacetTheme.canvas)
                .id("revision-\(selectedRevisionID ?? "")-\(revisionText.hashValue)")
            } else {
                ContentUnavailableView(
                    L10n.pick("Revision Unavailable", "无法读取历史版本"),
                    systemImage: "doc.badge.ellipsis",
                    description: Text(revisionError ?? L10n.pick("This file did not exist in that revision.",
                                                                 "该历史版本中不存在此文件。"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centeredPreview(_ doc: RepositoryDocument) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 18)
            previewPane(doc)
                .background(FacetTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.025), radius: 10, x: 0, y: 4)
                .frame(maxWidth: fullWidth ? .infinity : 900)
                .padding(.vertical, 18)
            Spacer(minLength: 18)
        }
        .background(FacetTheme.canvas)
    }

    private var centeredEditor: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 18)
            editorPane
                .background(FacetTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.025), radius: 10, x: 0, y: 4)
                .frame(maxWidth: fullWidth ? .infinity : 900)
                .padding(.vertical, 18)
            Spacer(minLength: 18)
        }
        .background(FacetTheme.canvas)
    }

    private var editorPane: some View {
        MarkdownEditor(text: $editorText, controller: editorController)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: editorText) { _, newText in autosave(newText) }
    }

    @ViewBuilder
    private func previewPane(_ doc: RepositoryDocument) -> some View {
        if editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                L10n.pick("Empty Note", "空白笔记"),
                systemImage: "square.and.pencil",
                description: Text(L10n.pick("Switch to Write to begin.", "切换到写作模式开始记录。"))
            )
        } else {
            MarkdownPreviewWeb(text: editorText, fullWidth: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(doc.id + "-\(editorText.hashValue)")
        }
    }

    private func labeledPane<Content: View>(_ title: String,
                                            systemImage: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(FacetTheme.quietPanel)
            Divider()
            content()
        }
        .background(FacetTheme.panel)
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func docControlBar(_ doc: RepositoryDocument) -> some View {
        WorkspaceActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text(doc.url.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                SelectionBadge(
                    text: L10n.pick("Read", "阅读"),
                    systemImage: "eye",
                    isActive: editorMode == .read,
                    help: L10n.pick("Read the rendered note", "阅读渲染后的笔记"),
                    onTap: { editorMode = .read }
                )
                .disabled(isViewingRevision)

                SelectionBadge(
                    text: L10n.pick("Write", "写作"),
                    systemImage: "square.and.pencil",
                    tint: .orange,
                    isActive: editorMode == .write,
                    help: L10n.pick("Edit the Markdown source", "编辑 Markdown 源文"),
                    onTap: { editorMode = .write }
                )
                .disabled(isViewingRevision)

                SelectionBadge(
                    text: L10n.pick("Split", "对照"),
                    systemImage: "rectangle.split.2x1",
                    tint: .purple,
                    isActive: editorMode == .split,
                    help: L10n.pick("Write with a live preview", "写作并实时预览"),
                    onTap: { editorMode = .split }
                )
                .disabled(isViewingRevision)
            }

            Spacer()

            HStack(spacing: FacetTheme.workspaceActionGroupSpacing) {
                WorkspaceActionGroup {
                    WorkspaceActionButton(
                        systemName: "sidebar.left",
                        help: navigatorVisible ? L10n.pick("Hide Navigator", "隐藏导航栏")
                                               : L10n.pick("Show Navigator", "显示导航栏"),
                        active: navigatorVisible
                    ) {
                        navigatorVisible.toggle()
                    }

                    WorkspaceActionButton(
                        systemName: "paperclip",
                        help: L10n.pick("Attach to Work Item", "关联到工作项")
                    ) {
                        showingAttachmentPopover = true
                    }
                    .popover(isPresented: $showingAttachmentPopover, arrowEdge: .bottom) {
                        documentAttachmentPopover(doc)
                    }

                    WorkspaceActionButton(
                        systemName: "clock.arrow.circlepath",
                        help: L10n.pick("Revision History", "版本历史"),
                        active: inspectorTab == .history && inspectorVisible
                    ) {
                        inspectorTab = .history
                        withAnimation(FacetTheme.detailSpring) { inspectorVisible = true }
                        reloadFileCommits()
                    }
                }

                WorkspaceActionGroup {
                    Menu {
                        Button(L10n.pick("Export to Markdown", "导出为 Markdown")) { exportToMarkdown() }
                        Button(L10n.pick("Export to PDF", "导出为 PDF")) { exportToPDF() }
                    } label: {
                        WorkspaceActionIcon(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L10n.pick("Export Document", "导出文档"))
                    .disabled(isViewingRevision)

                    WorkspaceActionButton(
                        systemName: "arrow.up.forward.app",
                        help: L10n.pick("Reveal in Finder", "在 Finder 中显示")
                    ) {
                        revealSelectedDocument()
                    }

                    if editorMode != .split {
                        WorkspaceActionButton(
                            systemName: fullWidth
                                ? "arrow.right.and.line.vertical.and.arrow.left"
                                : "arrow.left.and.line.vertical.and.arrow.right",
                            help: fullWidth ? L10n.pick("Constrain Width", "限制宽度")
                                            : L10n.pick("Full Width", "全宽显示"),
                            active: fullWidth
                        ) {
                            fullWidth.toggle()
                        }
                    }
                }

                WorkspaceActionGroup {
                    WorkspaceActionButton(
                        systemName: "sidebar.right",
                        help: inspectorVisible ? L10n.pick("Hide Note Details", "隐藏笔记详情")
                                               : L10n.pick("Show Note Details", "显示笔记详情"),
                        active: inspectorVisible
                    ) {
                        withAnimation(FacetTheme.detailSpring) { inspectorVisible.toggle() }
                    }
                }
            }
        }
    }

    private func documentStatusBar(_ doc: RepositoryDocument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(doc.relativePath)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(L10n.pick("\(lineCount) lines", "\(lineCount) 行"))
            Text("·")
            Text(L10n.pick("\(wordCount) words", "\(wordCount) 字"))
            Text("·")
            Text(fileSizeString)

            Divider().frame(height: 12)

            if let statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if isAutosaving {
                Label(L10n.pick("Saving", "正在保存"), systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else if hasUnsavedChanges {
                Label(L10n.pick("Unsaved", "未保存"), systemImage: "circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label(L10n.pick("Saved", "已保存"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.system(size: 9.5, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(FacetTheme.quietPanel)
    }

    private func documentAttachmentPopover(_ document: RepositoryDocument) -> some View {
        let workItems = items.filter { $0.kind == .reminder || $0.kind == .event }
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
        HStack(spacing: 3) {
            toolbarButton("arrow.uturn.backward", help: L10n.pick("Undo", "撤销")) { editorController.undo() }
            toolbarButton("arrow.uturn.forward", help: L10n.pick("Redo", "重做")) { editorController.redo() }
            Divider().frame(height: 15)
            toolbarButton("bold", help: "Bold ⌘B") { editorController.bold() }
            toolbarButton("italic", help: "Italic ⌘I") { editorController.italic() }
            toolbarButton("strikethrough", help: L10n.pick("Strikethrough", "删除线")) { editorController.strikethrough() }
            toolbarButton("chevron.left.forwardslash.chevron.right", help: L10n.pick("Inline Code", "行内代码")) { editorController.code() }
            toolbarButton("link", help: "Link ⌘K") { editorController.link() }
            Divider().frame(height: 15)
            Menu {
                ForEach(1...4, id: \.self) { level in
                    Button("H\(level)") { editorController.heading(level: level) }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.pick("Heading", "标题"))
            toolbarButton("list.bullet", help: L10n.pick("Bullet List", "项目列表")) { editorController.bulletList() }
            toolbarButton("list.number", help: L10n.pick("Numbered List", "编号列表")) { editorController.numberedList() }
            toolbarButton("checklist", help: L10n.pick("Task List", "任务列表")) { editorController.taskList() }
            toolbarButton("text.quote", help: L10n.pick("Quote", "引用")) { editorController.quote() }
            toolbarButton("curlybraces.square", help: L10n.pick("Code Block", "代码块")) { editorController.codeBlock() }
            toolbarButton("minus", help: L10n.pick("Divider", "分隔线")) { editorController.horizontalRule() }
            Spacer()
            Text(L10n.pick("Markdown · UTF-8", "Markdown · UTF-8"))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(FacetTheme.quietPanel)
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
        .facetHoverSurface(tint: .secondary,
                           fill: Color.clear,
                           hoverFill: Color.primary.opacity(0.055),
                           hoverStroke: FacetTheme.hairline)
        .help(help)
    }

    // MARK: - Actions & Loading

    private func reload() {
        let result = (try? RepositoryDocumentStore.list(repositoryPath: repoPath)) ?? []

        self.documents = result
        self.documentContentIndex = Dictionary(uniqueKeysWithValues: result.map { document in
            (document.id, (try? RepositoryDocumentStore.read(
                repositoryPath: repoPath,
                relativePath: document.relativePath
            )) ?? "")
        })

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
        autosaveTask?.cancel()
        if hasUnsavedChanges { saveSelectedDocument() }
        selectedDocumentID = document.id
        editorText = (try? RepositoryDocumentStore.read(
            repositoryPath: repoPath,
            relativePath: document.relativePath
        )) ?? ""
        savedText = editorText
        statusMessage = nil
    }

    private func reloadFileCommits() {
        guard let rootPath = repoPath.flatMap({ ($0 as NSString).expandingTildeInPath }),
              let doc = selectedDocument else {
            fileCommits = []
            isLoadingFileCommits = false
            return
        }

        let relativePath = doc.relativePath
        let documentID = doc.id
        isLoadingFileCommits = true
        Task {
            let commits = await LocalGitRepository.gitLogForFile(rootPath: rootPath, filePath: relativePath)
            await MainActor.run {
                guard selectedDocumentID == documentID else { return }
                self.fileCommits = commits
                self.isLoadingFileCommits = false
            }
        }
    }

    private func loadRevision(_ commit: LocalGitCommit) {
        guard let rootPath = repoPath.map({ ($0 as NSString).expandingTildeInPath }),
              let document = selectedDocument else { return }

        autosaveTask?.cancel()
        if hasUnsavedChanges { saveSelectedDocument() }
        revisionLoadGeneration += 1
        let generation = revisionLoadGeneration
        let documentID = document.id
        selectedRevisionID = commit.id
        revisionText = nil
        revisionError = nil
        isLoadingRevision = true

        Task {
            let content = await LocalGitRepository.fileContent(
                rootPath: rootPath,
                commitID: commit.id,
                filePath: document.relativePath
            )
            await MainActor.run {
                guard generation == revisionLoadGeneration,
                      selectedDocumentID == documentID,
                      selectedRevisionID == commit.id else { return }
                revisionText = content
                revisionError = content == nil
                    ? L10n.pick("This document did not exist at the selected commit.",
                                "所选提交中不存在这篇文档。")
                    : nil
                isLoadingRevision = false
            }
        }
    }

    private func clearRevision() {
        revisionLoadGeneration += 1
        selectedRevisionID = nil
        revisionText = nil
        revisionError = nil
        isLoadingRevision = false
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

    private func completeNaming(_ action: DocumentNamingAction, title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        do {
            let document: RepositoryDocument
            switch action {
            case .create:
                document = try RepositoryDocumentStore.create(
                    repositoryPath: repoPath,
                    title: normalized
                )
            case .rename(let existing):
                if selectedDocumentID == existing.id, hasUnsavedChanges { saveSelectedDocument() }
                document = try RepositoryDocumentStore.rename(
                    repositoryPath: repoPath,
                    relativePath: existing.relativePath,
                    title: normalized
                )
                for item in items {
                    guard let facetID = item.facetID else { continue }
                    let paths = ItemStore.shared.documentPaths(for: facetID)
                    guard paths.contains(existing.relativePath) else { continue }
                    ItemStore.shared.setDocumentPaths(
                        paths.map { $0 == existing.relativePath ? document.relativePath : $0 },
                        for: facetID
                    )
                }
                Task { await onItemsChanged() }
            }
            namingAction = nil
            reload()
            if let refreshed = documents.first(where: { $0.id == document.id }) {
                selectDocument(refreshed)
            }
            editorMode = .write
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deleteSelectedDocument() {
        guard let document = documentToDelete else { return }
        documentToDelete = nil
        do {
            if selectedDocumentID == document.id {
                autosaveTask?.cancel()
                selectedDocumentID = nil
                editorText = ""
                savedText = ""
            }
            try RepositoryDocumentStore.delete(
                repositoryPath: repoPath,
                relativePath: document.relativePath
            )
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func autosave(_ text: String) {
        guard let selectedDocument else { return }
        autosaveTask?.cancel()
        isAutosaving = true
        statusMessage = nil
        let path = selectedDocument.relativePath
        autosaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                guard editorText == text, selectedDocumentID == path else {
                    isAutosaving = false
                    return
                }
                try RepositoryDocumentStore.save(
                    repositoryPath: repoPath,
                    relativePath: path,
                    body: editorText
                )
                savedText = editorText
                documentContentIndex[path] = editorText
                isAutosaving = false
                reloadFileCommits()
            } catch is CancellationError {
                return
            } catch {
                isAutosaving = false
                statusMessage = error.localizedDescription
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
            documentContentIndex[selectedDocument.id] = editorText
            isAutosaving = false
            statusMessage = nil
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
                let exporter = MarkdownPDFExporter()
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
            let markerCount = trimmed.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(markerCount),
                  trimmed.dropFirst(markerCount).first == " " else { return nil }
            let text = trimmed.dropFirst(markerCount + 1)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : HeadingItem(level: markerCount, text: text)
        }
    }
}
