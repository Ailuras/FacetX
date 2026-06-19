import FacetXCore
import SwiftUI

struct TopicDetailView: View {
    let topic: TrackPref
    @Binding var tagFilter: TagFilter

    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var settings = LibrarySettings.shared
    @EnvironmentObject private var toast: ToastController
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var ek: EventKitService

    @State private var paperLinks: [String: Set<String>] = [:]
    @State private var searchText = ""
    @State private var selectedPaper: Paper?
    @State private var sortKey: SortKey = .score
    @State private var showAddSheet = false
    @State private var isRecommending = false
    @State private var isFetching = false
    @State private var collapsedSections: Set<ListSection> = []
    @State private var mode: Mode = .all
    @State private var paperToDelete: Paper?

    private let detailPaneAnimation = FacetTheme.detailSpring

    /// The collapsible sections of the paper list. Clicking a header toggles
    /// membership in `collapsedSections`, mirroring the project All view.
    enum ListSection: Hashable { case recommended, papers }

    enum Mode: String, CaseIterable, Identifiable {
        case all, starred, read, skipped
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:     return L10n.pick("All", "全部")
            case .starred: return L10n.pick("Starred", "收藏")
            case .read:    return L10n.pick("Read", "已读")
            case .skipped: return L10n.pick("Skipped", "已忽略")
            }
        }

        var status: PaperStatus? {
            switch self {
            case .all:     return nil
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
        guard mode == .all else { return [] }
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let paper = selectedPaper {
                    detailPane(for: paper)
                }
            }
            .animation(detailPaneAnimation, value: selectedPaper != nil)
        }
        .background(FacetTheme.canvas)
        .navigationTitle(topic.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, placeholder: L10n.t(.searchItems))
                    .frame(width: 220, height: 24)
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
        }
        .onChange(of: mode) {
            withAnimation(detailPaneAnimation) { selectedPaper = nil }
        }
        .onAppear {
            loadPaperLinks()
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
        .sheet(isPresented: $showAddSheet) {
            AddPaperView(topicName: topic.name) { papers in
                _ = store.addOrUpdate(papers: papers)
            }
        }
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

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            infoBar
            paperList
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
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 4, trailing: 14))

            if !collapsed {
                ForEach(papers) { paper in
                    PaperRow(paper: paper, isSelected: selectedPaper?.id == paper.id,
                             metadata: metadata, version: store.paperVersion,
                             linkedProjectPrefixes: paperLinks[paper.id] ?? [])
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
                        onTap: { setMode(.all) })
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
            FilterPillButton(systemName: "plus",
                             help: L10n.pick("Add paper", "添加文献")) {
                showAddSheet = true
            }
        }
        .pillGroupContainer()
    }

    // MARK: - Detail Pane

    private func detailPane(for paper: Paper) -> some View {
        FacetSidebarPane(
            title: L10n.pick("Paper", "文献"),
            systemImage: "doc.text",
            onClose: {
                withAnimation(detailPaneAnimation) { selectedPaper = nil }
            }
        ) {
            PaperDetailPane(inputPaper: paper, version: store.paperVersion)
        }
    }

    // MARK: - Toolbar

    private var toolbarActions: some View {
        HStack(spacing: 3) {
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
                        URLQueryItem(name: "select", value: "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access")
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
