import AppKit
import FacetXCore
import SwiftUI

/// Project Git workspace backed by a local repository. The view owns a small
/// `.facetx` markdown document area inside the repository root.
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

    @State private var documents: [FacetXRepoDocument] = []
    @State private var selectedDocumentID: FacetXRepoDocument.ID?
    @State private var editorText = ""
    @State private var savedText = ""
    @State private var statusMessage: String?
    @State private var repoInfo: LocalGitRepositoryInfo?
    @State private var detailFullscreen = false

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredDocuments: [FacetXRepoDocument] {
        guard !query.isEmpty else { return documents }
        return documents.filter { document in
            document.title.lowercased().contains(query)
                || document.url.lastPathComponent.lowercased().contains(query)
        }
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

    private var tokenStatus: (title: String, color: Color, icon: String) {
        settings.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (L10n.pick("Token missing", "未配置令牌"), .orange, "key.slash")
            : (L10n.pick("Token saved", "令牌已保存"), .green, "key")
    }

    var body: some View {
        HStack(spacing: 0) {
            if !detailFullscreen {
                VStack(spacing: 0) {
                    header
                    content
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
        .onAppear(perform: reload)
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
            if isShown, selectedDocument != nil, !detailFullscreen {
                selectedDocumentID = nil
            }
        }
        .onChange(of: showAssistantPanel.wrappedValue) { _, isShown in
            if isShown, selectedDocument != nil, !detailFullscreen {
                selectedDocumentID = nil
            }
        }
        .onChange(of: detailFullscreen) { _, isFullscreen in
            if isFullscreen {
                todayFullscreen.wrappedValue = false
                assistantFullscreen.wrappedValue = false
            }
        }
        .onChange(of: todayFullscreen.wrappedValue) { _, _ in
            selectedDocumentID = nil
            detailFullscreen = false
        }
        .onChange(of: assistantFullscreen.wrappedValue) { _, _ in
            selectedDocumentID = nil
            detailFullscreen = false
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            statusCard
            toolbar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            statusPill(title: L10n.pick("Local Repo", "本地仓库"),
                       value: repoPath.map { ($0 as NSString).lastPathComponent } ?? L10n.pick("Not bound", "未绑定"),
                       icon: "folder",
                       color: repoPath == nil ? .orange : .green)

            statusPill(title: "GitHub",
                       value: repoInfo?.fullName ?? project.githubRepo ?? L10n.pick("Not detected", "未识别"),
                       icon: "curlybraces",
                       color: (repoInfo?.fullName ?? project.githubRepo) == nil ? .secondary : .blue)

            statusPill(title: L10n.pick("Branch", "分支"),
                       value: repoInfo?.branch ?? L10n.pick("Unknown", "未知"),
                       icon: "arrow.triangle.branch",
                       color: repoInfo?.branch == nil ? .secondary : .purple)

            statusPill(title: L10n.pick("GitHub Token", "GitHub 令牌"),
                       value: tokenStatus.title,
                       icon: tokenStatus.icon,
                       color: tokenStatus.color)

            Spacer(minLength: 0)
        }
    }

    private func statusPill(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(L10n.pick("FacetX Docs", "FacetX 文档"))
                .font(.system(size: 12, weight: .semibold))
            Text("\(filteredDocuments.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            iconButton("arrow.clockwise", help: L10n.pick("Reload documents", "重新载入文档")) {
                reload()
            }
            iconButton("folder.badge.plus", help: L10n.pick("Initialize .facetx", "初始化 .facetx")) {
                initializeDocs()
            }
            iconButton("doc.badge.plus", help: L10n.pick("New document", "新建文档")) {
                createDocument()
            }
            .disabled(docsURL == nil)
            iconButton("arrow.up.forward.app", help: L10n.pick("Reveal .facetx in Finder", "在 Finder 中显示 .facetx")) {
                revealDocsFolder()
            }
            .disabled(docsURL == nil)
        }
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary,
                                   fill: Color.clear,
                                   hoverFill: Color.primary.opacity(0.055),
                                   hoverStroke: FacetTheme.hairline)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var content: some View {
        if repoURL == nil {
            emptyState(
                title: L10n.pick("Bind a Local Repository", "绑定本地仓库"),
                message: L10n.pick("Choose a local GitHub repository folder in the project editor. FacetX will use its .facetx folder as the project documentation area.",
                                   "在项目编辑器中选择一个本地 GitHub 仓库文件夹。FacetX 会使用其中的 .facetx 文件夹作为项目文档区。"),
                icon: "folder.badge.questionmark"
            )
        } else if documents.isEmpty {
            emptyState(
                title: L10n.pick("No FacetX Docs Yet", "还没有 FacetX 文档"),
                message: L10n.pick("Initialize .facetx to create a lightweight documentation area inside this repository.",
                                   "初始化 .facetx，在该仓库内创建轻量项目文档区。"),
                icon: "doc.text"
            )
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

    private func emptyState(title: String, message: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if repoURL != nil {
                Button {
                    initializeDocs()
                } label: {
                    Label(L10n.pick("Initialize Docs", "初始化文档区"), systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func documentRow(_ document: FacetXRepoDocument) -> some View {
        Button {
            select(document)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.11))
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

                if let modified = document.modifiedAt {
                    Text(relativeDate(modified))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedDocumentID == document.id ? Color.accentColor.opacity(0.10) : FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selectedDocumentID == document.id ? Color.accentColor.opacity(0.24) : FacetTheme.hairline,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var documentEditor: some View {
        FacetSidebarPane(
            title: selectedDocument?.title ?? L10n.pick("Document", "文档"),
            systemImage: "doc.text",
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
                    statusMessage = hasUnsavedChanges ? L10n.pick("Unsaved changes", "有未保存更改") : nil
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
            iconButton("square.and.arrow.down", help: L10n.pick("Save document", "保存文档")) {
                saveSelectedDocument()
            }
            .disabled(selectedDocument == nil || !hasUnsavedChanges)
            iconButton("arrow.up.forward.app", help: L10n.pick("Reveal document", "在 Finder 中显示文档")) {
                revealSelectedDocument()
            }
            iconButton(detailFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       help: detailFullscreen ? L10n.pick("Exit fullscreen", "退出全屏") : L10n.pick("Fullscreen", "全屏")) {
                detailFullscreen.toggle()
            }
        }
    }

    private func reload() {
        repoInfo = repoPath.flatMap(LocalGitRepository.inspect(path:))
        guard let docsURL else {
            documents = []
            selectedDocumentID = nil
            editorText = ""
            savedText = ""
            return
        }
        documents = loadDocuments(from: docsURL)
        if let selectedDocumentID, !documents.contains(where: { $0.id == selectedDocumentID }) {
            self.selectedDocumentID = nil
            editorText = ""
            savedText = ""
        }
    }

    private func initializeDocs() {
        guard let docsURL else { return }
        do {
            try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            let seeds: [(String, String)] = [
                ("README.md", "# \(project.name)\n\n## Overview\n\n## Current Focus\n\n## Links\n"),
                ("decisions.md", "# Decisions\n\n## Active Decisions\n\n## Resolved\n"),
                ("handoff.md", "# Handoff\n\n## Context\n\n## Next Steps\n")
            ]
            for seed in seeds {
                let url = docsURL.appendingPathComponent(seed.0)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try seed.1.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            statusMessage = L10n.pick(".facetx initialized", ".facetx 已初始化")
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
            try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
            reload()
            if let document = documents.first(where: { $0.url == url }) {
                select(document)
            }
        } catch {
            statusMessage = L10n.pick("Could not create document", "无法创建文档")
        }
    }

    private func select(_ document: FacetXRepoDocument) {
        if hasUnsavedChanges { saveSelectedDocument() }
        selectedDocumentID = document.id
        editorText = (try? String(contentsOf: document.url, encoding: .utf8)) ?? ""
        savedText = editorText
        statusMessage = nil
    }

    private func saveSelectedDocument() {
        guard let selectedDocument else { return }
        do {
            try editorText.write(to: selectedDocument.url, atomically: true, encoding: .utf8)
            savedText = editorText
            statusMessage = L10n.pick("Saved", "已保存")
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

    private func loadDocuments(from docsURL: URL) -> [FacetXRepoDocument] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: docsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return FacetXRepoDocument(url: url, modifiedAt: values?.contentModificationDate)
            }
            .sorted {
                ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
            }
    }

    private func uniqueDocumentURL(in directory: URL) -> URL {
        var index = 1
        while true {
            let filename = index == 1 ? "new-doc.md" : "new-doc-\(index).md"
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            index += 1
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct FacetXRepoDocument: Identifiable, Equatable {
    let url: URL
    let modifiedAt: Date?

    var id: String { url.path }

    var title: String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
