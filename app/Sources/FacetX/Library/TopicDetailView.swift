import FacetXCore
import PDFKit
import SwiftUI

struct TopicDetailView: View {
    let topic: TrackPref
    let showAssistantPanel: Binding<Bool>
    let assistantFullscreen: Binding<Bool>
    @Binding var tagFilter: TagFilter
    /// Held as a plain reference (not @ObservedObject): the reading view only
    /// writes the active-paper context into it and never needs to redraw when
    /// the session's own @Published state changes.
    let assistant: AssistantSession

    @State private var aiReadingContext = false

    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var settings = LibrarySettings.shared
    @EnvironmentObject private var toast: ToastController
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var focus: FocusService

    @State private var paperLinks: [String: Set<String>] = [:]
    @State private var searchText = ""
    @State private var selectedPaper: Paper?
    @State private var sortKey: SortKey = .score
    @State private var isRecommending = false
    @State private var showImportSidebar = false
    @State private var importFullscreen = false
    @State private var detailFullscreen = false
    @State private var isFetching = false
    @State private var onlineSearchQuery = ""
    @State private var activeScholarQuery = ""
    @State private var paperBeingImported: Paper? = nil
    @State private var importedPaperTitles: Set<String> = []
    @State private var collapsedSections: Set<ListSection> = []
    @State private var mode: Mode = .all
    @State private var showRecommended = true
    @State private var paperToDelete: Paper?

    @State private var viewMode: ViewMode = .library
    @State private var readingPaperID: String? = nil
    @State private var reader = PdfReaderModel()
    @State private var pdfSearchText = ""
    @State private var showPdfSidebar = false
    @State private var pdfSidebarTab: PdfSidebarTab = .outline
    @State private var showTranslationPopover = false
    @State private var isTranslatingSelection = false
    @State private var translatedSelectionText = ""
    @State private var translationSelectionError: String? = nil

    enum PdfSidebarTab: String, CaseIterable, Identifiable {
        case outline, annotations
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .outline: return L10n.pick("Outline", "大纲")
            case .annotations: return L10n.pick("Annotations", "批注")
            }
        }
    }

    private let detailPaneAnimation = FacetTheme.detailSpring

    /// Top-level layout of the literature view.
    enum ViewMode: Hashable { case library, reading, onlineSearch, dashboard }

    /// The collapsible sections of the paper list. Clicking a header toggles
    /// membership in `collapsedSections`, mirroring the project All view.
    enum ListSection: Hashable { case recommended, papers }

    enum Mode: String, CaseIterable, Identifiable {
        case all, pending, starred, read, skipped
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:     return L10n.pick("All", "全部")
            case .pending: return L10n.pick("Pending", "待读")
            case .starred: return L10n.pick("Starred", "收藏")
            case .read:    return L10n.pick("Read", "已读")
            case .skipped: return L10n.pick("Skipped", "已忽略")
            }
        }

        var status: PaperStatus? {
            switch self {
            case .all:     return nil
            case .pending: return .pending
            case .starred: return .starred
            case .read:    return .read
            case .skipped: return .skip
            }
        }
    }

    // MARK: - Derived Lists

    private var papersForTopic: [Paper] {
        store.papers.filter { paper in
            paper.track.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains(topic.name)
        }
    }

    private func matchesSearch(_ paper: Paper) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        return tokens.allSatisfy { paper.searchText.contains($0) }
    }

    /// Search text plus the sidebar tag filter (shared with projects).
    private func matchesFilters(_ paper: Paper) -> Bool {
        matchesSearch(paper) && tagFilter.matches(tags: paper.tags)
    }

    /// Daily recommendations, pinned at the top of the All view.
    private var recommendedPapers: [Paper] {
        guard showRecommended, mode == .all else { return [] }
        let calendar = Calendar.current
        return papersForTopic
            .filter { paper in
                guard paper.isRecommended, let date = paper.recommendedAt else { return false }
                return calendar.isDateInToday(date) && matchesFilters(paper)
            }
            .sorted { $0.score > $1.score }
    }

    /// The main list below the recommendations, scoped by the active mode.
    private var listedPapers: [Paper] {
        var result = papersForTopic.filter(matchesFilters)
        if let status = mode.status {
            result = result.filter { $0.status == status }
        } else {
            // In All view, recommended papers live in their own pinned section.
            let recommendedIds = Set(recommendedPapers.map(\.id))
            result = result.filter { !recommendedIds.contains($0.id) }
        }
        return sorted(result)
    }

    private func sorted(_ papers: [Paper]) -> [Paper] {
        let ascending = settings.sortAscending
        var result = papers
        switch sortKey {
        case .score:
            result.sort { ascending ? $0.score < $1.score : $0.score > $1.score }
        case .publicationDate:
            result.sort { ascending ? $0.publicationDate < $1.publicationDate : $0.publicationDate > $1.publicationDate }
        case .citations:
            result.sort { ascending ? $0.citedByCount < $1.citedByCount : $0.citedByCount > $1.citedByCount }
        case .statusTime:
            result.sort {
                let l = $0.statusChangedAt ?? .distantPast
                let r = $1.statusChangedAt ?? .distantPast
                return ascending ? l < r : l > r
            }
        case .dateAdded:
            result.sort {
                let l = $0.addedAt ?? .distantPast
                let r = $1.addedAt ?? .distantPast
                return ascending ? l < r : l > r
            }
        case .title:
            result.sort {
                let cmp = $0.title.localizedCaseInsensitiveCompare($1.title)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
        return result
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasActiveFilter: Bool {
        hasActiveSearch || !tagFilter.isEmpty
    }

    private var visibleCount: Int { recommendedPapers.count + listedPapers.count }

    // MARK: - Body

    var body: some View {
        let base = VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !importFullscreen && !detailFullscreen {
                    content
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }

                if showImportSidebar {
                    importPane
                }

                if let paper = selectedPaper {
                    detailPane(for: paper)
                }
            }
            .animation(detailPaneAnimation, value: showImportSidebar)
            .animation(detailPaneAnimation, value: selectedPaper != nil)
            .animation(detailPaneAnimation, value: importFullscreen)
            .animation(detailPaneAnimation, value: detailFullscreen)
        }
        .background(FacetTheme.canvas)
        .navigationTitle(topic.name)
        .toolbar {
            ToolbarItem(placement: .status) {
                viewModePicker
            }
            ToolbarItem(placement: .automatic) {
                if viewMode == .library {
                    ToolbarSearchField(text: $searchText, placeholder: L10n.t(.searchItems))
                        .frame(width: 220, height: 24)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .onChange(of: store.paperVersion) {
            if let paper = selectedPaper,
               !store.papers.contains(where: { $0.id == paper.id }) {
                withAnimation(detailPaneAnimation) { selectedPaper = nil }
            }
            if viewMode == .reading { syncReader() }
        }
        .onChange(of: mode) {
            withAnimation(detailPaneAnimation) { selectedPaper = nil }
        }
        .onChange(of: viewMode) { _, newValue in
            if newValue == .reading { syncReader() } else { syncPaperContext() }
        }
        .onChange(of: readingPaperID) {
            if viewMode == .reading { syncReader() }
        }
        .modifier(ReadingContextObservers(
            currentPage: reader.currentPage,
            selectionText: reader.selectionText,
            onPageChange: syncPaperContext,
            onSelectionChange: syncSelectionToAssistant,
            onDisappear: { assistant.activePaperContext = nil }
        ))
        .onAppear {
            loadPaperLinks()
            loadImportedTitles()
            if viewMode == .reading { syncReader() }
        }
        .onChange(of: ek.changeToken) { _, _ in
            loadPaperLinks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPaperInTopic)) { notification in
            guard let paperID = notification.userInfo?["paperID"] as? String else { return }
            if let paper = store.papers.first(where: { $0.id == paperID }) {
                selectedPaper = paper
            }
        }

        return applySidebarObservers(base)
            .alert(L10n.pick("Delete this paper?", "删除该文献？"), isPresented: .init(
                get: { paperToDelete != nil },
                set: { if !$0 { paperToDelete = nil } }
            )) {
                Button(L10n.pick("Cancel", "取消"), role: .cancel) { paperToDelete = nil }
                Button(L10n.pick("Delete", "删除"), role: .destructive) {
                    if let paper = paperToDelete {
                        deletePaper(paper)
                    }
                    paperToDelete = nil
                }
            } message: {
                Text(paperToDelete?.title ?? "")
            }
    }

    @ViewBuilder
    private func applySidebarObservers<V: View>(_ content: V) -> some View {
        content
            .onChange(of: selectedPaper?.id) { _, newValue in
                if newValue != nil {
                    if showAssistantPanel.wrappedValue {
                        detailFullscreen = true
                    }
                } else {
                    detailFullscreen = false
                }
            }
            .onChange(of: showImportSidebar) { _, newValue in
                if newValue {
                    if showAssistantPanel.wrappedValue {
                        importFullscreen = true
                    }
                } else {
                    importFullscreen = false
                    paperBeingImported = nil
                }
            }
            .onChange(of: showAssistantPanel.wrappedValue) { _, isShown in
                if isShown {
                    if !detailFullscreen && !importFullscreen && (selectedPaper != nil || showImportSidebar) {
                        withAnimation(detailPaneAnimation) {
                            selectedPaper = nil
                            showImportSidebar = false
                            detailFullscreen = false
                            importFullscreen = false
                        }
                    }
                }
            }
            .onChange(of: detailFullscreen) { _, isFullscreen in
                if isFullscreen {
                    assistantFullscreen.wrappedValue = false
                }
            }
            .onChange(of: importFullscreen) { _, isFullscreen in
                if isFullscreen {
                    assistantFullscreen.wrappedValue = false
                }
            }
            .onChange(of: assistantFullscreen.wrappedValue) { _, _ in
                withAnimation(detailPaneAnimation) {
                    selectedPaper = nil
                    showImportSidebar = false
                    detailFullscreen = false
                    importFullscreen = false
                }
            }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            switch viewMode {
            case .library:
                infoBar
                paperList
            case .reading:
                readingBar
                pdfReader
            case .onlineSearch:
                onlineSearchBar
                onlineSearchView
            case .dashboard:
                dashboardView
            }
        }
    }

    private var viewModePicker: some View {
        Picker("", selection: $viewMode) {
            Text(L10n.pick("Library", "文库")).tag(ViewMode.library)
            Text(L10n.pick("Read", "阅读")).tag(ViewMode.reading)
            Text(L10n.pick("Search", "检索")).tag(ViewMode.onlineSearch)
            Text(L10n.pick("Graph", "图谱")).tag(ViewMode.dashboard)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .help(L10n.pick("Switch views: Library / Reading / Online Search / Citation Graph",
                        "切换视图：本地文库 / 沉浸阅读 / 云端检索 / 引文与关系图谱"))
    }



    @ViewBuilder private var dashboardView: some View {
        PaperGraphView(papers: papersForTopic, metadata: metadata) { paper in
            withAnimation(detailPaneAnimation) {
                selectedPaper = selectedPaper?.id == paper.id ? nil : paper
            }
        }
    }

    // MARK: - Reading (PDF) view

    /// Papers in this topic that have a locally available PDF — the only ones
    /// the in-app reader can render.
    private var papersWithPdf: [Paper] {
        papersForTopic
            .filter { PdfCoordinator.hasLocalPdf($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The paper currently open in the reader: the explicit pick, or the first
    /// available PDF as a sensible default.
    private var readingPaper: Paper? {
        if let id = readingPaperID, let match = papersWithPdf.first(where: { $0.id == id }) {
            return match
        }
        return papersWithPdf.first
    }

    private var readingURL: URL? {
        guard let path = readingPaper?.pdfLocalPath, !path.isEmpty else { return nil }
        return PdfStorage.current().absoluteURL(forRelative: path)
    }

    private func syncReader() {
        if let url = readingURL {
            reader.load(url: url)
        } else {
            reader.clear()
        }
        syncPaperContext()
    }

    /// Reflect the reading state into the assistant session's paper context.
    /// Full text is extracted only when the paper actually changes; a plain page
    /// turn just refreshes the volatile page counters so we don't re-parse the
    /// whole PDF on every scroll.
    private func syncPaperContext() {
        guard aiReadingContext, viewMode == .reading, let paper = readingPaper else {
            if assistant.activePaperContext != nil { assistant.activePaperContext = nil }
            return
        }
        if assistant.activePaperContext?.paperID == paper.id {
            assistant.activePaperContext?.currentPage = reader.currentPage
            assistant.activePaperContext?.pageCount = reader.pageCount
            return
        }
        let (fullText, truncated) = extractReadingText(for: paper)
        assistant.activePaperContext = ActivePaperContext(
            paperID: paper.id,
            title: paper.title,
            authors: paper.authors.joined(separator: ", "),
            abstract: paper.abstract,
            fullText: fullText,
            truncated: truncated,
            currentPage: reader.currentPage,
            pageCount: reader.pageCount
        )
    }

    /// Extract the paper's text for context injection, capped so a very long PDF
    /// can't blow the model's context window; the model can still pull specific
    /// pages verbatim via `read_paper` when it hits the truncation marker.
    private func extractReadingText(for paper: Paper) -> (text: String, truncated: Bool) {
        guard let path = paper.pdfLocalPath, !path.isEmpty,
              let document = PDFDocument(url: PdfStorage.current().absoluteURL(forRelative: path)) else {
            return ("", false)
        }
        var text = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            text += "\n--- page \(index + 1) ---\n" + pageText
        }
        let cap = 48_000
        if text.count > cap { return (String(text.prefix(cap)), true) }
        return (text, false)
    }

    private func toggleReadingContext() {
        aiReadingContext.toggle()
        syncPaperContext()
        if aiReadingContext { showAssistantPanel.wrappedValue = true }
    }

    /// Mirror the current PDF selection into the composer's "quote" chip while
    /// the reading context is on. PDFKit hands us the selection as a plain
    /// string, so no parsing is required.
    private func syncSelectionToAssistant() {
        guard aiReadingContext else { return }
        // Keep the last non-empty selection so clicking into the composer (which
        // clears the PDF selection) doesn't drop the quote before it's sent.
        let selection = reader.selectionText
        if !selection.isEmpty {
            assistant.pendingSelection = selection
        }
    }

    private var readingBar: some View {
        HStack(spacing: 10) {
            if reader.pageCount > 0 {
                HStack(spacing: 2) {
                    FilterPillButton(
                        systemName: "sidebar.left",
                        help: L10n.pick("Toggle PDF Sidebar", "切换 PDF 大纲与批注"),
                        active: showPdfSidebar
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showPdfSidebar.toggle()
                        }
                    }
                }
                .pillGroupContainer()
            }
            paperDropdown
            if readingPaper != nil {
                HStack(spacing: 2) {
                    FilterPillButton(
                        systemName: aiReadingContext ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack",
                        help: aiReadingContext
                            ? L10n.pick("AI is reading this paper — click to stop sharing it", "AI 正以此文献为上下文 — 点击停止共享")
                            : L10n.pick("Share this paper with the AI assistant as context", "把当前文献作为上下文提供给 AI 助手"),
                        active: aiReadingContext
                    ) {
                        toggleReadingContext()
                    }
                }
                .pillGroupContainer()
            }
            Spacer()
            if reader.pageCount > 0 {
                pdfToolCluster
            }
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var paperDropdown: some View {
        Menu {
            if papersWithPdf.isEmpty {
                Text(L10n.pick("No papers with a PDF yet", "暂无包含 PDF 的文献"))
            } else {
                ForEach(papersWithPdf) { paper in
                    Button {
                        readingPaperID = paper.id
                    } label: {
                        if paper.id == readingPaper?.id {
                            Label(paper.title, systemImage: "checkmark")
                        } else {
                            Text(paper.title)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 24)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(FacetTheme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(readingPaper?.title ?? L10n.pick("Choose a paper to read", "选择要阅读的文献"))
    }

    private var pdfToolCluster: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                pdfSearchField
                FilterPillButton(systemName: "chevron.left",
                                 help: L10n.pick("Previous page", "上一页")) { reader.previousPage() }
                Text("\(reader.currentPage) / \(reader.pageCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52)
                FilterPillButton(systemName: "chevron.right",
                                 help: L10n.pick("Next page", "下一页")) { reader.nextPage() }
            }
            .pillGroupContainer()

            HStack(spacing: 2) {
                FilterPillButton(systemName: "minus.magnifyingglass",
                                 help: L10n.pick("Zoom out", "缩小")) { reader.zoomOut() }
                FilterPillButton(systemName: "arrow.left.and.right",
                                 help: L10n.pick("Fit width", "适应宽度")) { reader.fitWidth() }
                FilterPillButton(systemName: "plus.magnifyingglass",
                                 help: L10n.pick("Zoom in", "放大")) { reader.zoomIn() }
            }
            .pillGroupContainer()

            // Annotation tools (highlighting and text notes)
            HStack(spacing: 3) {
                ForEach(PdfHighlightColor.allCases) { color in
                    Button {
                        reader.highlightCurrentSelection(color: color.nsColor)
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!reader.hasSelection)
                    .opacity(reader.hasSelection ? 1.0 : 0.35)
                    .hoverCursor(.pointingHand)
                    .help(color.displayName)
                }

                Divider().frame(height: 16)

                FilterPillButton(systemName: "note.text.badge.plus",
                                 help: L10n.pick("Add Sticky Note", "添加便签"),
                                 active: false) {
                    reader.addNoteToSelection()
                }
                .disabled(!reader.hasSelection)
                .opacity(reader.hasSelection ? 1.0 : 0.35)

                FilterPillButton(systemName: "globe",
                                 help: L10n.pick("Translate Selection", "翻译选中文本"),
                                 active: showTranslationPopover) {
                    translateSelectedText()
                }
                .disabled(!reader.hasSelection)
                .opacity(reader.hasSelection ? 1.0 : 0.35)
                .popover(isPresented: $showTranslationPopover) {
                    translationPopoverView
                }

                if reader.activeAnnotation != nil {
                    FilterPillButton(systemName: "trash",
                                     help: L10n.pick("Delete Annotation", "删除选中的批注"),
                                     active: false) {
                        reader.deleteActiveAnnotation()
                    }
                }
            }
            .padding(.horizontal, 4)
            .pillGroupContainer()

            HStack(spacing: 2) {
                FilterPillButton(
                    systemName: "sidebar.right",
                    help: L10n.pick("Toggle paper details", "切换文献详情"),
                    active: selectedPaper?.id == readingPaper?.id
                ) {
                    if let paper = readingPaper {
                        withAnimation(detailPaneAnimation) {
                            if selectedPaper?.id == paper.id {
                                selectedPaper = nil
                            } else {
                                selectedPaper = paper
                            }
                        }
                    }
                }
            }
            .pillGroupContainer()
        }
    }

    private var pdfSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField(L10n.pick("Find in PDF", "在 PDF 中查找"), text: $pdfSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 100)
                .onSubmit { reader.find(pdfSearchText) }
        }
        .padding(.horizontal, 8)
        .frame(height: FacetTheme.chipHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(FacetTheme.quietPanel))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(FacetTheme.hairline, lineWidth: 1))
    }

    private func translateSelectedText() {
        guard let selectionString = reader.pdfView.currentSelection?.string, !selectionString.isEmpty else {
            translationSelectionError = L10n.pick("No text selected", "未选中文本")
            showTranslationPopover = true
            return
        }

        isTranslatingSelection = true
        translationSelectionError = nil
        translatedSelectionText = ""
        showTranslationPopover = true

        let settings = LibrarySettings.shared
        let config = ConfigManager.shared.effectiveConfig

        Task { @MainActor in
            do {
                let translator = TranslationService(config: config, apiKey: settings.apiKey)
                let result = try await translator.translateText(selectionString)
                self.translatedSelectionText = result
                self.isTranslatingSelection = false
            } catch {
                self.translationSelectionError = error.localizedDescription
                self.isTranslatingSelection = false
            }
        }
    }

    private var translationPopoverView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pick("Translation Result", "翻译结果"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            if isTranslatingSelection {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .frame(minHeight: 60)
            } else if let error = translationSelectionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(minWidth: 220)
            } else {
                ScrollView {
                    Text(translatedSelectionText)
                        .font(.system(size: 11))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)

                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translatedSelectionText, forType: .string)
                    } label: {
                        Label(L10n.pick("Copy", "复制"), systemImage: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var pdfSidebarPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pdfSidebarTab) {
                ForEach(PdfSidebarTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().frame(height: 1)

            ScrollView {
                if pdfSidebarTab == .outline {
                    if reader.outlineItems.isEmpty {
                        VStack(spacing: 12) {
                            Spacer().frame(height: 40)
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text(L10n.pick("No outline available", "暂无目录大纲"))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(reader.outlineItems) { item in
                                Button {
                                    reader.pdfView.go(to: item.destination)
                                } label: {
                                    Text(item.title)
                                        .font(.system(size: 11, weight: item.depth == 0 ? .semibold : .regular))
                                        .foregroundStyle(item.depth == 0 ? .primary : .secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .padding(.leading, CGFloat(item.depth * 10 + 8))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverCursor(.pointingHand)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.clear)
                                )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    if reader.annotations.isEmpty {
                        VStack(spacing: 12) {
                            Spacer().frame(height: 40)
                            Image(systemName: "highlighter")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text(L10n.pick("No annotations yet", "暂无批注记录"))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(reader.annotations) { ann in
                                Button {
                                    if let page = ann.annotation.page {
                                        let dest = PDFDestination(page: page, at: CGPoint(x: ann.annotation.bounds.minX, y: ann.annotation.bounds.maxY))
                                        reader.pdfView.go(to: dest)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(ann.color)
                                                .frame(width: 8, height: 8)
                                            Text(ann.type == "Highlight" ? L10n.pick("Highlight", "高亮") : L10n.pick("Note", "便签"))
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(L10n.pick("P. \(ann.pageIndex + 1)", "第 \(ann.pageIndex + 1) 页"))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(ann.text)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(FacetTheme.quietPanel)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(FacetTheme.hairline, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .hoverCursor(.pointingHand)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(FacetTheme.canvas)
    }

    @ViewBuilder private var pdfReader: some View {
        if readingURL != nil {
            HStack(spacing: 0) {
                if showPdfSidebar {
                    pdfSidebarPanel
                        .resizableSidebarWidth(
                            storageKey: "facetPdfSidebarWidth",
                            defaultWidth: 220,
                            minWidth: 180,
                            maxWidth: 420,
                            handleEdge: .trailing
                        )
                        .transition(.move(edge: .leading))

                    Rectangle()
                        .fill(FacetTheme.hairline)
                        .frame(width: 1)
                        .ignoresSafeArea()
                }

                PdfReaderRepresentable(model: reader)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    .background(FacetTheme.canvas)
            }
        } else {
            ContentUnavailableView {
                Label(L10n.pick("Nothing to read yet", "暂无可阅读内容"), systemImage: "book.closed")
            } description: {
                Text(L10n.pick("Attach or fetch a PDF for a paper, then pick it from the dropdown above.",
                               "为文献附加或拉取 PDF 后，可在上方下拉中选择阅读。"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Paper List

    @ViewBuilder private var paperList: some View {
        if visibleCount == 0 {
            emptyState
        } else {
            List {
                if !recommendedPapers.isEmpty {
                    paperSection(
                        section: .recommended,
                        title: L10n.pick("Daily Recommendations", "每日推荐"),
                        systemImage: "sparkles",
                        color: .orange,
                        papers: recommendedPapers
                    )
                }
                paperSection(
                    section: .papers,
                    title: mode == .all ? L10n.pick("Papers", "文献") : mode.title,
                    systemImage: mode == .all ? "doc.text" : (mode.status?.iconName ?? "doc.text"),
                    color: .accentColor,
                    papers: listedPapers
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .thinScrollIndicators()
        }
    }

    @ViewBuilder
    private func paperSection(section: ListSection, title: String, systemImage: String,
                              color: Color, papers: [Paper]) -> some View {
        if !papers.isEmpty {
            let collapsed = collapsedSections.contains(section)
            sectionHeader(title: title, systemImage: systemImage, count: papers.count,
                          color: color, collapsed: collapsed)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(detailPaneAnimation) { toggleCollapse(section) } }
                .hoverCursor(.pointingHand)
                .help(collapsed ? L10n.pick("Expand section", "展开分区")
                                : L10n.pick("Collapse section", "折叠分区"))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 4, trailing: 14))

            if !collapsed {
                ForEach(papers) { paper in
                    PaperRow(paper: paper, isSelected: selectedPaper?.id == paper.id,
                             metadata: metadata, version: store.paperVersion,
                             linkedProjectPrefixes: paperLinks[paper.id] ?? [],
                             onPdfBadgeTap: {
                                 readingPaperID = paper.id
                                 viewMode = .reading
                             })
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                        .onTapGesture { toggleSelection(paper) }
                        .contextMenu { paperContextMenu(for: paper) }
                }
            }
        }
    }

    private func toggleCollapse(_ section: ListSection) {
        if collapsedSections.contains(section) { collapsedSections.remove(section) }
        else { collapsedSections.insert(section) }
    }

    private func sectionHeader(title: String, systemImage: String, count: Int,
                               color: Color, collapsed: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
        .foregroundStyle(.primary.opacity(0.86))
    }

    private func toggleSelection(_ paper: Paper) {
        withAnimation(detailPaneAnimation) {
            selectedPaper = (selectedPaper?.id == paper.id) ? nil : paper
        }
    }

    // MARK: - Context Menu

    /// All per-paper actions live here so the sidebar pane stays optional —
    /// status, recommendation, tags, links, citations and delete are reachable
    /// straight from a right-click on the row.
    @ViewBuilder
    private func paperContextMenu(for paper: Paper) -> some View {
        let linkedPrefixes = paperLinks[paper.id] ?? []
        let availableProjects = projectStore.activeProjects.filter { !linkedPrefixes.contains($0.prefix) }

        if !availableProjects.isEmpty {
            Menu {
                ForEach(availableProjects) { project in
                    Button(project.name) {
                        addPaperToProject(paper, project: project)
                    }
                }
            } label: {
                Label(L10n.pick("Add to Project", "添加到项目"), systemImage: "folder.badge.plus")
            }
            Divider()
        }

        Button {
            store.setPaperStatus(id: paper.id,
                                 status: paper.status == .starred ? .pending : .starred)
        } label: {
            Label(paper.status == .starred ? L10n.pick("Unstar", "取消收藏") : L10n.pick("Star", "收藏"),
                  systemImage: paper.status == .starred ? "star.slash" : "star")
        }

        if focus.isFocusing(paper.focusTargetID) {
            Button {
                focus.finish()
            } label: {
                Label(L10n.pick("End Focus", "结束专注"), systemImage: "timer")
            }
        } else {
            Button {
                focus.start(target: paper.focusTarget(topicLabel: topic.name),
                            minutes: appSettings.focusDurationMinutes)
            } label: {
                Label(L10n.pick("Start Focus (\(appSettings.focusDurationMinutes) min)",
                                "开始专注（\(appSettings.focusDurationMinutes) 分钟）"),
                      systemImage: "timer")
            }
        }

        Menu {
            ForEach(PaperStatus.allCases, id: \.self) { status in
                Button {
                    store.setPaperStatus(id: paper.id, status: status)
                } label: {
                    Label(statusName(status),
                          systemImage: paper.status == status ? "checkmark" : status.iconName)
                }
            }
        } label: {
            Label(L10n.pick("Set Status", "设置状态"), systemImage: "flag")
        }

        Button {
            store.setPaperRecommended(id: paper.id, isRecommended: !paper.isRecommended)
        } label: {
            Label(paper.isRecommended ? L10n.pick("Remove Recommendation", "取消推荐")
                                      : L10n.pick("Recommend", "推荐"),
                  systemImage: paper.isRecommended ? "minus.circle" : "sparkles")
        }

        if !store.allTags.isEmpty {
            Menu {
                ForEach(store.allTags, id: \.self) { tag in
                    Button {
                        if paper.tags.contains(tag) {
                            store.removePaperTag(id: paper.id, tag: tag)
                        } else {
                            store.addPaperTag(id: paper.id, tag: tag)
                        }
                    } label: {
                        Label(tag, systemImage: paper.tags.contains(tag) ? "checkmark" : "tag")
                    }
                }
            } label: {
                Label(L10n.pick("Tags", "标签"), systemImage: "tag")
            }
        }

        Button {
            if selectedPaper?.id != paper.id { toggleSelection(paper) }
        } label: {
            Label(L10n.pick("Edit Details…", "编辑详情…"), systemImage: "sidebar.right")
        }

        Divider()

        if !paper.landingPageUrl.isEmpty {
            Button {
                if let url = URL(string: paper.landingPageUrl) { NSWorkspace.shared.open(url) }
            } label: {
                Label(L10n.pick("Open Source Page", "打开原文"), systemImage: "arrow.up.right.square")
            }
        }
        if PdfCoordinator.hasLocalPdf(paper) {
            Button {
                _ = PdfCoordinator.reveal(paper: paper)
            } label: {
                Label(L10n.pick("Show PDF in Finder", "在访达中显示 PDF"), systemImage: "folder")
            }
        }

        Menu {
            Button(L10n.pick("Title", "标题")) {
                copyToPasteboard(paper.title, label: L10n.pick("Title", "标题"))
            }
            Divider()
            Button("BibTeX") {
                copyToPasteboard(CitationExporter.bibtex(for: paper), label: "BibTeX")
            }
            Button("APA") {
                copyToPasteboard(CitationExporter.apa(for: paper), label: "APA")
            }
            Button("RIS") {
                copyToPasteboard(CitationExporter.ris(for: paper), label: "RIS")
            }
            Button("Markdown") {
                copyToPasteboard(CitationExporter.markdown(for: paper), label: "Markdown")
            }
        } label: {
            Label(L10n.pick("Copy", "复制"), systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            paperToDelete = paper
        } label: {
            Label(L10n.pick("Delete", "删除"), systemImage: "trash")
        }
    }

    private func statusName(_ status: PaperStatus) -> String {
        switch status {
        case .pending: return L10n.pick("Pending", "待读")
        case .read:    return L10n.pick("Read", "已读")
        case .starred: return L10n.pick("Starred", "收藏")
        case .skip:    return L10n.pick("Skip", "忽略")
        }
    }

    private func copyToPasteboard(_ string: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        toast.show(L10n.pick("\(label) copied", "\(label) 已复制"),
                   type: .success, duration: 1.6)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                hasActiveFilter ? L10n.pick("No results", "无结果") : emptyTitle,
                systemImage: hasActiveFilter ? "magnifyingglass" : emptyIcon
            )
        } description: {
            Text(emptyMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch mode {
        case .all:     return L10n.pick("No papers in this topic", "该主题暂无文献")
        case .pending: return L10n.pick("No pending papers", "暂无待读")
        case .starred: return L10n.pick("No starred papers", "暂无收藏")
        case .read:    return L10n.pick("No papers read", "暂无已读")
        case .skipped: return L10n.pick("No skipped papers", "暂无忽略")
        }
    }

    private var emptyIcon: String {
        mode == .all ? "doc.text" : (mode.status?.iconName ?? "doc.text")
    }

    private var emptyMessage: String {
        if hasActiveSearch {
            return L10n.pick("No papers match “\(searchText)”.", "没有匹配“\(searchText)”的文献。")
        }
        if !tagFilter.isEmpty {
            return L10n.pick("No papers match the active tag filter.", "没有匹配当前标签筛选的文献。")
        }
        if mode == .all {
            return L10n.pick("Use Fetch to pull recent papers, or + to add manually.",
                             "点击拉取获取近期文献，或用 + 手动添加。")
        }
        return L10n.pick("Papers you mark will appear here.", "标记后的文献会显示在这里。")
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        HStack(spacing: 10) {
            modeCluster

            if !tagFilter.isEmpty {
                ActiveTagFilterBar(tagFilter: $tagFilter)
            }

            Spacer()

            if hasActiveSearch {
                FacetInfoBadge(
                    text: L10n.pick("\(visibleCount) results", "\(visibleCount) 条结果"),
                    systemImage: "magnifyingglass",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }

            actionCluster
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    /// Clickable count badges that replace the old segmented mode picker: the
    /// "All" chip clears the status filter, and each status chip isolates papers
    /// of that status (clicking the active one returns to All). Mirrors the
    /// project All view's summary cluster.
    private var modeCluster: some View {
        HStack(spacing: 6) {
            SummaryChip(value: papersForTopic.count,
                        label: L10n.pick("All", "全部"),
                        systemImage: "square.grid.2x2",
                        isActive: mode == .all,
                        help: L10n.pick("Show all papers", "显示全部文献"),
                        onTap: { setMode(.all) })
            modeChip(.pending)
            modeChip(.starred)
            modeChip(.read)
            modeChip(.skipped)
        }
    }

    private func modeChip(_ m: Mode) -> some View {
        let status = m.status
        let count = papersForTopic.filter { $0.status == status }.count
        return SummaryChip(value: count,
                           label: m.title,
                           systemImage: status?.iconName ?? "doc.text",
                           tint: status?.iconColor,
                           isActive: mode == m,
                           help: L10n.pick("Show \(m.title)", "显示\(m.title)"),
                           onTap: { setMode(m) })
    }

    /// Click a chip to focus that status; click the active chip again to reset.
    private func setMode(_ m: Mode) {
        withAnimation(detailPaneAnimation) {
            mode = (mode == m) ? .all : m
        }
    }

    private var actionCluster: some View {
        HStack(spacing: 2) {
            sortMenu
            FilterPillButton(
                systemName: "sparkles",
                help: showRecommended ? L10n.pick("Hide recommendations", "隐藏推荐文献")
                                      : L10n.pick("Show recommendations", "显示推荐文献"),
                active: showRecommended
            ) {
                withAnimation(detailPaneAnimation) {
                    showRecommended.toggle()
                }
            }
            FilterPillButton(systemName: "plus",
                             help: L10n.pick("Add paper", "添加文献"),
                             active: showImportSidebar && paperBeingImported?.id.hasPrefix("gs-") != true) {
                withAnimation(detailPaneAnimation) {
                    showImportSidebar.toggle()
                    if showImportSidebar {
                        selectedPaper = nil
                        paperBeingImported = Paper(id: "man-\(UUID().uuidString)", title: "", track: topic.name)
                    } else {
                        paperBeingImported = nil
                    }
                }
            }
        }
        .pillGroupContainer()
    }

    // MARK: - Detail Pane

    private func detailPane(for paper: Paper) -> some View {
        FacetSidebarPane(
            title: L10n.pick("Paper", "文献"),
            systemImage: "doc.text",
            fillWidth: detailFullscreen,
            onClose: {
                withAnimation(detailPaneAnimation) { selectedPaper = nil }
            },
            accessory: { detailFullscreenToggle }
        ) {
            PaperDetailPane(inputPaper: paper, version: store.paperVersion)
        }
    }

    private var detailFullscreenToggle: some View {
        Button {
            withAnimation(detailPaneAnimation) {
                detailFullscreen.toggle()
                showAssistantPanel.wrappedValue = false
                assistantFullscreen.wrappedValue = false
            }
        } label: {
            Image(systemName: detailFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(detailFullscreen ? L10n.pick("Exit fullscreen", "退出全屏")
                               : L10n.pick("Fullscreen", "全屏"))
    }

    // MARK: - Import Pane
    
    private var importPane: some View {
        FacetSidebarPane(
            title: paperBeingImported?.id.hasPrefix("gs-") == true
                ? L10n.pick("Import Literature", "导入文献")
                : L10n.pick("Add Literature", "添加文献"),
            systemImage: "square.and.arrow.down",
            fillWidth: importFullscreen,
            onClose: {
                withAnimation(detailPaneAnimation) {
                    showImportSidebar = false
                    paperBeingImported = nil
                }
            },
            accessory: { importFullscreenToggle }
        ) {
            AddPaperView(
                topicName: topic.name,
                initialPaper: paperBeingImported,
                onSave: { paper, pdfData, pdfFilename in
                    _ = store.addOrUpdate(papers: [paper])
                    if let data = pdfData, pdfFilename != nil {
                        do {
                            let relative = try PdfStorage.current().write(data, forPaperId: paper.id)
                            paper.pdfLocalPath = relative
                            paper.pdfStatus = PdfStatus.downloaded.rawValue
                            _ = store.addOrUpdate(papers: [paper])
                            
                            PaperStore.shared.savePdf(id: paper.id, result: PdfFetchResult(
                                status: .downloaded,
                                url: paper.pdfUrl,
                                source: "manual-import",
                                localPath: relative,
                                byteSize: data.count,
                                sha256: PdfStorage.sha256Hex(data)
                            ))
                        } catch {
                            print("Failed to save PDF on import: \(error)")
                        }
                    } else if let pdfUrl = paper.pdfUrl, !pdfUrl.isEmpty {
                        Task { @MainActor in
                            let result = await PdfCoordinator.fetch(paper: paper, store: store)
                            if result.status == .downloaded {
                                toast.show(
                                    L10n.pick("PDF downloaded for “\(paper.title)”", "“\(paper.title)” 的 PDF 下载完成"),
                                    type: .success,
                                    duration: 2
                                )
                            }
                        }
                    }
                    
                    toast.show(
                        L10n.pick("Imported paper “\(paper.title)” to library", "已成功导入文献 “\(paper.title)”"),
                        type: .success,
                        duration: 2
                    )
                    
                    loadImportedTitles()
                    
                    withAnimation(detailPaneAnimation) {
                        showImportSidebar = false
                        paperBeingImported = nil
                    }
                },
                onCancel: {
                    withAnimation(detailPaneAnimation) {
                        showImportSidebar = false
                        paperBeingImported = nil
                    }
                }
            )
        }
    }

    private var importFullscreenToggle: some View {
        Button {
            withAnimation(detailPaneAnimation) {
                importFullscreen.toggle()
                showAssistantPanel.wrappedValue = false
                assistantFullscreen.wrappedValue = false
            }
        } label: {
            Image(systemName: importFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(importFullscreen ? L10n.pick("Exit fullscreen", "退出全屏")
                               : L10n.pick("Fullscreen", "全屏"))
    }

    private var importFullscreenTogglePlaceholder: some View {
        EmptyView()
    }

    // MARK: - Search View & Helpers

    private var onlineSearchBar: some View {
        HStack(spacing: 8) {
            TextField(L10n.pick("Search papers on Google Scholar...", "在谷歌学术检索学术文献…"), text: $onlineSearchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 350)
                .onSubmit {
                    activeScholarQuery = onlineSearchQuery
                }

            Button {
                activeScholarQuery = onlineSearchQuery
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onlineSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            
            Spacer()
            
            HStack(spacing: 2) {
                FilterPillButton(
                    systemName: "house",
                    help: L10n.pick("Scholar Home", "学术首页"),
                    active: activeScholarQuery.isEmpty || activeScholarQuery == "https://scholar.google.com/" || activeScholarQuery == "https://scholar.google.com"
                ) {
                    onlineSearchQuery = ""
                    activeScholarQuery = "https://scholar.google.com/"
                }
                
                FilterPillButton(
                    systemName: "person.crop.circle",
                    help: L10n.pick("My Profile (Followed Authors)", "个人中心 (关注作者)"),
                    active: activeScholarQuery == "https://scholar.google.com/citations"
                ) {
                    onlineSearchQuery = ""
                    activeScholarQuery = "https://scholar.google.com/citations"
                }
                
                FilterPillButton(
                    systemName: "bookmark",
                    help: L10n.pick("My Library (Starred)", "我的图书馆 (收藏)"),
                    active: activeScholarQuery == "https://scholar.google.com/scholar?scilib=1"
                ) {
                    onlineSearchQuery = ""
                    activeScholarQuery = "https://scholar.google.com/scholar?scilib=1"
                }
            }
            .pillGroupContainer()
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var onlineSearchView: some View {
        GoogleScholarWebView(query: activeScholarQuery, importedTitles: importedPaperTitles) { metadata in
            handleScholarImport(metadata)
        }
    }

    private func handleScholarImport(_ metadata: [String: Any]) {
        let title = metadata["title"] as? String ?? ""
        let authors = metadata["authors"] as? [String] ?? []
        let venue = metadata["venue"] as? String ?? ""
        let year = metadata["year"] as? Int
        let snippet = metadata["snippet"] as? String ?? ""
        let url = metadata["url"] as? String ?? ""
        let pdfUrl = metadata["pdfUrl"] as? String

        let paper = Paper(
            id: "gs-\(UUID().uuidString)",
            title: title,
            authors: authors,
            publicationYear: year,
            venue: venue,
            abstract: snippet,
            landingPageUrl: url,
            pdfUrl: pdfUrl,
            track: topic.name,
            addedAt: Date()
        )

        withAnimation(detailPaneAnimation) {
            paperBeingImported = paper
            showImportSidebar = true
            selectedPaper = nil
        }
    }

    private func loadImportedTitles() {
        let existing = store.papers.map { $0.title }
        importedPaperTitles = Set(existing)
    }

    // MARK: - Toolbar

    private var toolbarActions: some View {
        HStack(spacing: 3) {
            Button {
                withAnimation(FacetTheme.detailSpring) {
                    showAssistantPanel.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: showAssistantPanel.wrappedValue ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showAssistantPanel.wrappedValue ? Color.accentColor : .primary)
            }
            .help(showAssistantPanel.wrappedValue
                  ? L10n.pick("Hide AI assistant", "隐藏 AI 助手")
                  : L10n.pick("Show AI assistant", "显示 AI 助手"))
            recommendButton
            fetchButton
        }
    }

    private var recommendButton: some View {
        Button {
            recommend()
        } label: {
            if isRecommending {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sun.max")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .disabled(isRecommending)
        .help(L10n.pick("Generate daily recommendations", "生成每日推荐"))
    }

    private var fetchButton: some View {
        Button {
            fetchPapers()
        } label: {
            if isFetching {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .disabled(isFetching)
        .help(L10n.pick("Fetch papers from the last 40 days", "拉取近 40 天文献"))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortKey.allCases) { key in
                Button {
                    sortKey = key
                    settings.sortKeyRaw = key.rawValue
                } label: {
                    HStack {
                        Image(systemName: key.systemImage)
                        Text(key.title)
                        if sortKey == key { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button {
                settings.sortAscending.toggle()
            } label: {
                HStack {
                    Image(systemName: settings.sortAscending ? "arrow.up" : "arrow.down")
                    Text(settings.sortAscending ? L10n.pick("Ascending", "升序") : L10n.pick("Descending", "降序"))
                }
            }
        } label: {
            Image(systemName: sortKey.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(sortKey == .score ? .secondary : Color.accentColor)
                .frame(width: 26, height: 24)
                .background(sortKey == .score ? Color.clear : Color.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.pick("Sort: \(sortKey.title)", "排序：\(sortKey.title)"))
    }

    // MARK: - Actions

    private func recommend() {
        let pool = papersForTopic
        guard !pool.isEmpty else {
            toast.show(L10n.pick("No papers to recommend yet", "暂无可推荐的文献"), type: .info, duration: 2)
            return
        }
        isRecommending = true
        // Accumulate: recommend only papers that aren't already in the set, so
        // clicking again the same day adds fresh picks instead of replacing the
        // previous ones (which made it look like only the latest 3 ever stuck).
        let candidates = pool.filter { !$0.isRecommended }
        let engine = RecommendEngine(config: ConfigManager.shared.effectiveConfig)
        let results = engine.recommend(papers: candidates)
        for result in results {
            store.setPaperRecommended(id: result.paper.id, isRecommended: true, reason: "")
        }
        withAnimation(detailPaneAnimation) { mode = .all }
        isRecommending = false
        if results.isEmpty {
            toast.show(L10n.pick("No more papers to recommend", "没有更多可推荐的文献"),
                       type: .info, duration: 2)
        } else {
            toast.show(L10n.pick("Recommended \(results.count) more papers", "新增推荐 \(results.count) 篇"),
                       type: .success, duration: 2)
        }
    }

    private func fetchPapers() {
        guard !topic.query.trimmingCharacters(in: .whitespaces).isEmpty else {
            toast.show(L10n.pick("This topic has no search query configured", "该主题尚未配置检索式"),
                       type: .warning, duration: 2.5)
            return
        }

        isFetching = true

        Task {
            do {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                guard let fromDay = Calendar.current.date(byAdding: .day, value: -40, to: Date()) else { return }
                let fromDate = dateFormatter.string(from: fromDay)
                let toDate = dateFormatter.string(from: Date())

                var allWorks: [OpenAlexWork] = []
                var cursor: String? = "*"
                let perPage = min(settings.perPage, 100)
                var count = 0
                let maxResults = min(settings.defaultMaxResults, 200)
                let cfg = ConfigManager.shared.effectiveConfig

                while count < maxResults, let c = cursor {
                    var filters = ["from_publication_date:\(fromDate)", "to_publication_date:\(toDate)", "type:article"]
                    if !cfg.openalex.topic_filter.isEmpty {
                        filters.append(cfg.openalex.topic_filter)
                    }
                    var components = URLComponents(string: cfg.openalex.base_url)
                    components?.queryItems = [
                        URLQueryItem(name: "search", value: topic.query),
                        URLQueryItem(name: "filter", value: filters.joined(separator: ",")),
                        URLQueryItem(name: "sort", value: "publication_date:desc,relevance_score:desc"),
                        URLQueryItem(name: "per_page", value: String(perPage)),
                        URLQueryItem(name: "cursor", value: c),
                        URLQueryItem(name: "select", value: "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access,referenced_works,related_works")
                    ]
                    if !settings.openAlexMailto.isEmpty {
                        components?.queryItems?.append(URLQueryItem(name: "mailto", value: settings.openAlexMailto))
                    }
                    guard let url = components?.url else { break }

                    var request = URLRequest(url: url)
                    var userAgent = "FacetX/1.0"
                    if !settings.openAlexMailto.isEmpty { userAgent += " (mailto:\(settings.openAlexMailto))" }
                    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { break }
                    let alexResponse = try JSONDecoder().decode(OpenAlexResponse.self, from: data)
                    guard let results = alexResponse.results, !results.isEmpty else { break }
                    allWorks.append(contentsOf: results)
                    count += results.count
                    cursor = alexResponse.meta?.nextCursor
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                let fetcher = OpenAlexFetcher(config: cfg, venues: MetadataStore.shared.venues)
                let papers = allWorks.map { fetcher.parseWork($0, track: topic.name) }

                let relevant = topic.keywords.isEmpty ? papers : papers.filter { paper in
                    let text = (paper.title + " " + paper.abstract).lowercased()
                    return topic.keywords.contains { keyword in
                        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword.lowercased()))\\b"
                        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
                        return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
                    }
                }

                let (inserted, updated) = store.addOrUpdate(papers: relevant)
                isFetching = false
                toast.show(L10n.pick("Fetched \(relevant.count) papers (\(inserted) new, \(updated) updated)",
                                     "拉取 \(relevant.count) 篇（新增 \(inserted)，更新 \(updated)）"),
                           type: .success, duration: 3)
            } catch {
                isFetching = false
                toast.show(L10n.pick("Fetch failed: \(error.localizedDescription)",
                                     "拉取失败：\(error.localizedDescription)"), type: .error)
            }
        }
    }

    private func addPaperToProject(_ paper: Paper, project: Project) {
        let listName: String
        if let projList = project.literatureListName, !projList.isEmpty {
            listName = projList
        } else if !appSettings.defaultLiteratureListName.isEmpty {
            listName = appSettings.defaultLiteratureListName
        } else if !appSettings.defaultReminderListName.isEmpty {
            listName = appSettings.defaultReminderListName
        } else {
            toast.show(L10n.pick("No paper list configured. Please set a default or project paper list.", "未配置文献列表，请在设置或项目属性中指定。"), type: .warning)
            return
        }

        let paperUrl = URL(string: paper.landingPageUrl)

        let reminderMetadata = FacetItemMetadata(
            itemID: UUID().uuidString,
            paperIDs: [paper.id],
            commits: [],
            tags: []
        )

        Task {
            let reminderId = await ek.createReminder(
                project: project.prefix,
                content: paper.title,
                listName: listName,
                dueDate: nil,
                dueIncludesTime: false,
                itemMetadata: reminderMetadata,
                url: paperUrl,
                enabledLists: appSettings.effectiveReminderListNames
            )

            if reminderId != nil {
                toast.show(L10n.pick("Added paper to project “\(project.name)”", "已将文献添加到项目“\(project.name)”"), type: .success, duration: 2)
                await MainActor.run {
                    loadPaperLinks()
                }
            } else {
                toast.show(L10n.pick("Failed to add paper", "添加文献失败"), type: .error)
            }
        }
    }

    private func deletePaper(_ paper: Paper) {
        if selectedPaper?.id == paper.id {
            withAnimation(detailPaneAnimation) { selectedPaper = nil }
        }
        Task {
            _ = await PaperLinkCleanup.removePaperIDs(
                [paper.id],
                projectStore: projectStore,
                appSettings: appSettings,
                ek: ek
            )
            store.deletePapers(ids: [paper.id])
            toast.show(L10n.pick("Paper deleted", "已删除文献"), type: .success, duration: 2)
        }
    }

    private func loadPaperLinks() {
        Task {
            let prefixes = Set(projectStore.activeProjects.map(\.prefix))
            let allItems = await ek.itemsLinkedToPapers(
                forProjects: prefixes,
                enabledReminderLists: appSettings.effectiveReminderListNames,
                enabledCalendars: appSettings.effectiveCalendarNames
            )
            var map: [String: Set<String>] = [:]
            for item in allItems {
                for paperId in item.linkedPaperIDs {
                    map[paperId, default: []].insert(item.projectPrefix)
                }
            }
            self.paperLinks = map
        }
    }
}

/// Bundles the reading-view → assistant observers into one modifier so they
/// don't inflate `TopicDetailView.body` past the Swift type-checker's budget.
private struct ReadingContextObservers: ViewModifier {
    let currentPage: Int
    let selectionText: String
    let onPageChange: () -> Void
    let onSelectionChange: () -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: currentPage) { onPageChange() }
            .onChange(of: selectionText) { onSelectionChange() }
            .onDisappear { onDisappear() }
    }
}
