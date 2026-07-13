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

/// Project Git workspace: real local git log + working-tree status on the left;
/// .facetx documentation area (plus root README) as an optional side pane.
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

    // ── Git state ─────────────────────────────────────────────────────────────
    @State private var repoInfo: LocalGitRepositoryInfo?
    @State private var commits: [LocalGitCommit] = []
    @State private var statusEntries: [LocalGitStatusEntry] = []
    @State private var isLoadingGit = false
    @State private var selectedCommitID: String?
    @State private var expandedCommitID: String?

    // ── Document state ────────────────────────────────────────────────────────
    @State private var documents: [FacetXRepoDocument] = []
    @State private var selectedDocumentID: FacetXRepoDocument.ID?
    @State private var editorText = ""
    @State private var savedText = ""
    @State private var docStatusMessage: String?
    @State private var detailFullscreen = false

    // ── Layout tab ────────────────────────────────────────────────────────────
    private enum Tab: String, CaseIterable {
        case git   = "Git"
        case docs  = "Docs"
    }
    @State private var tab: Tab = .git

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

    private var filteredCommits: [LocalGitCommit] {
        guard !query.isEmpty else { return commits }
        return commits.filter {
            $0.summary.lowercased().contains(query) ||
            $0.shortSHA.lowercased().contains(query) ||
            $0.authorName.lowercased().contains(query)
        }
    }

    private var filteredDocuments: [FacetXRepoDocument] {
        guard !query.isEmpty else { return documents }
        return documents.filter { $0.title.lowercased().contains(query) }
    }

    /// Build a reverse index: commit SHA (short or full) → [ProjectItem] for
    /// items in this project that have linked commits in this repo.
    private var linkedItemsByCommit: [String: [ProjectItem]] {
        var result: [String: [ProjectItem]] = [:]
        let repoFullName = repoInfo?.fullName ?? project.githubRepo
        for item in items {
            for commitStr in item.linkedCommits {
                // Format: "owner/repo@sha"
                let parts = commitStr.split(separator: "@")
                guard parts.count == 2 else { continue }
                let commitRepo = String(parts[0])
                let sha = String(parts[1])
                // Match by repo name if known; otherwise include all
                if let repoFullName, !commitRepo.isEmpty, commitRepo != repoFullName {
                    continue
                }
                result[sha, default: []].append(item)
                // Also index by short SHA for matching against git log output
                let short = String(sha.prefix(7))
                if short != sha {
                    result[short, default: []].append(item)
                }
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            if !detailFullscreen {
                VStack(spacing: 0) {
                    topBar
                    if repoURL == nil {
                        noRepoState
                    } else {
                        tabContent
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }

            if selectedDocument != nil {
                documentEditor
            }
        }
        .background(FacetTheme.canvas)
        .animation(FacetTheme.detailSpring, value: selectedDocumentID)
        .animation(FacetTheme.detailSpring, value: detailFullscreen)
        .onAppear { reload() }
        .onChange(of: project.id) { reload() }
        .onChange(of: project.githubLocalPath) { reload() }
        .onChange(of: refreshTrigger) { reload() }
        .onChange(of: searchText) {
            if let selectedDocumentID,
               !filteredDocuments.contains(where: { $0.id == selectedDocumentID }) {
                self.selectedDocumentID = nil
                detailFullscreen = false
            }
        }
        .onChange(of: showTodayPanel.wrappedValue) { _, isShown in
            if isShown, selectedDocument != nil, !detailFullscreen { selectedDocumentID = nil }
        }
        .onChange(of: showAssistantPanel.wrappedValue) { _, isShown in
            if isShown, selectedDocument != nil, !detailFullscreen { selectedDocumentID = nil }
        }
        .onChange(of: detailFullscreen) { _, isFullscreen in
            if isFullscreen {
                todayFullscreen.wrappedValue = false
                assistantFullscreen.wrappedValue = false
            }
        }
        .onChange(of: todayFullscreen.wrappedValue) { _, _ in
            selectedDocumentID = nil; detailFullscreen = false
        }
        .onChange(of: assistantFullscreen.wrappedValue) { _, _ in
            selectedDocumentID = nil; detailFullscreen = false
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Status pills
                repoStatusPill
                if let info = repoInfo {
                    branchPill(info)
                }
                Spacer(minLength: 0)
                // Tab picker
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                // Refresh
                Button {
                    reloadGit()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                        .facetHoverSurface(tint: .secondary, fill: .clear,
                                           hoverFill: Color.primary.opacity(0.055),
                                           hoverStroke: FacetTheme.hairline)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Refresh", "刷新"))
                .disabled(isLoadingGit)
                // Docs actions (only in docs tab)
                if tab == .docs {
                    docsToolbarButtons
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
        .background(FacetTheme.canvas)
    }

    private var repoStatusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(repoPath == nil ? Color.orange : .green)
                .frame(width: 6, height: 6)
            Text(repoPath.map { ($0 as NSString).lastPathComponent }
                    ?? L10n.pick("No repo", "未绑定"))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(FacetTheme.quietPanel)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(FacetTheme.hairline, lineWidth: 1))
    }

    private func branchPill(_ info: LocalGitRepositoryInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.purple)
            Text(info.branch ?? "—")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.purple.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.purple.opacity(0.22), lineWidth: 1))
    }

    private var docsToolbarButtons: some View {
        HStack(spacing: 2) {
            iconButton("folder.badge.plus",
                       help: L10n.pick("Initialize .facetx", "初始化 .facetx")) {
                initializeDocs()
            }
            iconButton("doc.badge.plus",
                       help: L10n.pick("New document", "新建文档")) {
                createDocument()
            }
            .disabled(docsURL == nil)
            iconButton("arrow.up.forward.app",
                       help: L10n.pick("Reveal .facetx in Finder", "在 Finder 中显示 .facetx")) {
                revealDocsFolder()
            }
            .disabled(docsURL == nil)
        }
    }

    private func iconButton(_ systemImage: String, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary, fill: Color.clear,
                                   hoverFill: Color.primary.opacity(0.055),
                                   hoverStroke: FacetTheme.hairline)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Tab content

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .git:  gitView
        case .docs: docsView
        }
    }

    // MARK: - Git view

    private var gitView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Working-tree status
                if !statusEntries.isEmpty {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(statusEntries) { entry in
                                statusRow(entry)
                                if entry.id != statusEntries.last?.id {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    } header: {
                        sectionHeader(
                            icon: "circle.dotted",
                            title: L10n.pick("Working Changes", "工作区变更"),
                            count: statusEntries.count,
                            tint: statusEntries.contains { !$0.staged } ? .orange : .green
                        )
                    }
                }

                // Commit log
                Section {
                    if isLoadingGit {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else if filteredCommits.isEmpty {
                        Text(commits.isEmpty
                             ? L10n.pick("No commits yet.", "暂无提交记录。")
                             : L10n.pick("No matches.", "无匹配。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredCommits) { commit in
                                commitRow(commit)
                                if commit.id != filteredCommits.last?.id {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                } header: {
                    sectionHeader(
                        icon: "clock.arrow.circlepath",
                        title: L10n.pick("Commit History", "提交历史"),
                        count: filteredCommits.count,
                        tint: .purple
                    )
                }
            }
        }
        .thinScrollIndicators()
    }

    private func sectionHeader(icon: String, title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    // ── Status row ────────────────────────────────────────────────────────────

    private func statusRow(_ entry: LocalGitStatusEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(stateColor(entry.state))
                .frame(width: 20)

            Text(entry.path)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text(entry.staged
                 ? L10n.pick("Staged", "已暂存")
                 : L10n.pick("Unstaged", "未暂存"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(entry.staged ? Color.green : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((entry.staged ? Color.green : Color.orange).opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func stateColor(_ state: LocalGitStatusEntry.State) -> Color {
        switch state {
        case .modified:   return .orange
        case .added:      return .green
        case .deleted:    return .red
        case .renamed:    return .blue
        case .untracked:  return .secondary
        case .other:      return .secondary
        }
    }

    // ── Commit row ────────────────────────────────────────────────────────────

    private func commitRow(_ commit: LocalGitCommit) -> some View {
        let isExpanded = expandedCommitID == commit.id
        let linkedItems = linkedItemsByCommit[commit.id]
            ?? linkedItemsByCommit[commit.shortSHA]
            ?? []
        let repoFullName = repoInfo?.fullName ?? project.githubRepo

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedCommitID = isExpanded ? nil : commit.id
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    // Commit graph dot
                    ZStack {
                        Circle()
                            .stroke(Color.purple.opacity(0.30), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        if !commit.refs.isEmpty {
                            Circle()
                                .fill(Color.purple.opacity(0.65))
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .fill(Color.purple.opacity(0.30))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 20)
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        // Summary line + ref badges
                        HStack(spacing: 6) {
                            Text(commit.summary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(isExpanded ? 10 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !commit.refs.isEmpty {
                                ForEach(commit.refs.components(separatedBy: ", ").prefix(2), id: \.self) { ref in
                                    refBadge(ref)
                                }
                            }
                        }

                        // Meta line
                        HStack(spacing: 8) {
                            Text(commit.shortSHA)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.purple.opacity(0.8))
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(commit.authorName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(relativeDate(commit.date))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            if !linkedItems.isEmpty {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(L10n.pick("\(linkedItems.count) task\(linkedItems.count == 1 ? "" : "s")",
                                              "\(linkedItems.count) 个任务"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        // Expanded: body + linked tasks + open on GitHub button
                        if isExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                if let body = commit.body {
                                    Text(body)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                if !linkedItems.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(linkedItems, id: \.id) { item in
                                            HStack(spacing: 6) {
                                                Image(systemName: item.facetKind.systemImage)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(item.facetKind.color)
                                                Text(item.content)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.accentColor.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                if let url = commit.htmlURL(repoFullName: repoFullName) {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label(L10n.pick("View on GitHub", "在 GitHub 查看"),
                                              systemImage: "arrow.up.right.square")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .background(expandedCommitID == commit.id
                    ? Color.purple.opacity(0.04) : Color.clear)
    }

    private func refBadge(_ ref: String) -> some View {
        let isHEAD = ref.hasPrefix("HEAD")
        let isOrigin = ref.hasPrefix("origin/")
        let tint: Color = isHEAD ? .orange : (isOrigin ? .blue : .purple)
        return Text(ref)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Docs view

    private var docsView: some View {
        Group {
            if documents.isEmpty {
                docsEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredDocuments) { document in
                            documentRow(document)
                        }
                    }
                    .padding(16)
                }
                .thinScrollIndicators()
            }
        }
    }

    private var docsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.pick("No FacetX Docs Yet", "还没有 FacetX 文档"))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.pick(
                "Initialize .facetx to create the documentation folder inside this repository. FacetX also reads the project's root README.md.",
                "初始化 .facetx 文件夹作为项目文档区。FacetX 同时读取仓库根目录的 README.md。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                initializeDocs()
            } label: {
                Label(L10n.pick("Initialize .facetx", "初始化 .facetx"),
                      systemImage: "folder.badge.plus")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func documentRow(_ document: FacetXRepoDocument) -> some View {
        Button { selectDocument(document) } label: {
            HStack(spacing: 10) {
                Image(systemName: document.isReadme ? "doc.richtext" : "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(document.isReadme ? Color.orange : Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background((document.isReadme ? Color.orange : Color.accentColor).opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(document.url.lastPathComponent)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if document.isReadme {
                    Text("README")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                }

                if let modified = document.modifiedAt {
                    Text(relativeDate(modified))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedDocumentID == document.id
                        ? Color.accentColor.opacity(0.10) : FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selectedDocumentID == document.id
                            ? Color.accentColor.opacity(0.24) : FacetTheme.hairline,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - No-repo state

    private var noRepoState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.pick("Bind a Local Repository", "绑定本地仓库"))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.pick(
                "Choose a local Git repository folder in the project editor.",
                "在项目编辑器中选择一个本地 Git 仓库文件夹。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Document editor

    private var documentEditor: some View {
        FacetSidebarPane(
            title: selectedDocument?.title ?? L10n.pick("Document", "文档"),
            systemImage: selectedDocument?.isReadme == true ? "doc.richtext" : "doc.text",
            closeHelp: L10n.pick("Close document", "关闭文档"),
            fillWidth: detailFullscreen,
            onClose: {
                if hasUnsavedChanges { saveSelectedDocument() }
                selectedDocumentID = nil
                detailFullscreen = false
            },
            accessory: { editorToolbar }
        ) {
            TextEditor(text: $editorText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(FacetTheme.canvas)
                .onChange(of: editorText) {
                    docStatusMessage = hasUnsavedChanges
                        ? L10n.pick("Unsaved changes", "有未保存更改") : nil
                }
        }
        .frame(minWidth: detailFullscreen ? 0 : 360)
    }

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            if hasUnsavedChanges {
                Text(L10n.pick("Unsaved", "未保存"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            iconButton("square.and.arrow.down",
                       help: L10n.pick("Save document", "保存文档")) {
                saveSelectedDocument()
            }
            .disabled(selectedDocument == nil || !hasUnsavedChanges)
            iconButton("arrow.up.forward.app",
                       help: L10n.pick("Reveal in Finder", "在 Finder 中显示")) {
                revealSelectedDocument()
            }
            iconButton(detailFullscreen
                       ? "arrow.down.right.and.arrow.up.left"
                       : "arrow.up.left.and.arrow.down.right",
                       help: detailFullscreen
                            ? L10n.pick("Exit fullscreen", "退出全屏")
                            : L10n.pick("Fullscreen", "全屏")) {
                detailFullscreen.toggle()
            }
        }
    }

    // MARK: - Data loading

    private func reload() {
        repoInfo = repoPath.flatMap(LocalGitRepository.inspect(path:))
        reloadGit()
        reloadDocs()
    }

    private func reloadGit() {
        guard let rootPath = repoInfo?.rootPath else {
            commits = []; statusEntries = []; return
        }
        isLoadingGit = true
        Task {
            async let log = LocalGitRepository.gitLog(rootPath: rootPath)
            async let status = LocalGitRepository.gitStatus(rootPath: rootPath)
            let (c, s) = await (log, status)
            await MainActor.run {
                commits = c
                statusEntries = s
                isLoadingGit = false
            }
        }
    }

    private func reloadDocs() {
        var result: [FacetXRepoDocument] = []

        // 1. Root README.md
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

        // 2. .facetx/*.md files
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

        documents = result

        // Drop selected document if it no longer exists
        if let selectedDocumentID,
           !documents.contains(where: { $0.id == selectedDocumentID }) {
            self.selectedDocumentID = nil
            editorText = ""; savedText = ""
        }
    }

    // MARK: - Document actions

    /// Initialize .facetx — just creates the folder, no seed files.
    private func initializeDocs() {
        guard let docsURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: docsURL, withIntermediateDirectories: true)
            reloadDocs()
            tab = .docs
        } catch {
            docStatusMessage = L10n.pick("Could not initialize .facetx",
                                         "无法初始化 .facetx")
        }
    }

    private func createDocument() {
        guard let docsURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: docsURL, withIntermediateDirectories: true)
            let url = uniqueDocumentURL(in: docsURL)
            let title = url.deletingPathExtension().lastPathComponent
            try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
            reloadDocs()
            if let doc = documents.first(where: { $0.url == url }) {
                selectDocument(doc)
            }
        } catch {
            docStatusMessage = L10n.pick("Could not create document", "无法创建文档")
        }
    }

    private func selectDocument(_ document: FacetXRepoDocument) {
        if hasUnsavedChanges { saveSelectedDocument() }
        selectedDocumentID = document.id
        editorText = (try? String(contentsOf: document.url, encoding: .utf8)) ?? ""
        savedText = editorText
        docStatusMessage = nil
    }

    private func saveSelectedDocument() {
        guard let selectedDocument else { return }
        do {
            try editorText.write(to: selectedDocument.url, atomically: true, encoding: .utf8)
            savedText = editorText
            docStatusMessage = L10n.pick("Saved", "已保存")
            reloadDocs()
        } catch {
            docStatusMessage = L10n.pick("Could not save document", "无法保存文档")
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
