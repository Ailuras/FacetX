import SwiftUI

struct TopicDetailView: View {
    let topic: TrackPref

    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var settings = LibrarySettings.shared
    @EnvironmentObject private var toast: ToastController

    @State private var searchText = ""
    @State private var selectedPaper: Paper?
    @State private var sortKey: SortKey = .score
    @State private var showAddSheet = false
    @State private var isRecommending = false
    @State private var isFetching = false
    @State private var mode: Mode = .all

    private let detailPaneAnimation = FacetTheme.detailSpring

    enum Mode: String, CaseIterable, Identifiable {
        case all, starred, read, skipped
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:     return L10n.pick("All", "全部")
            case .starred: return L10n.pick("Starred", "收藏")
            case .read:    return L10n.pick("Read", "已读")
            case .skipped: return L10n.pick("Skipped", "忽略")
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

    // MARK: - Derived collections

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

    /// Daily recommendations, pinned at the top of the All view.
    private var recommendedPapers: [Paper] {
        guard mode == .all else { return [] }
        return papersForTopic
            .filter { $0.isRecommended && matchesSearch($0) }
            .sorted { $0.score > $1.score }
    }

    /// The main list below the recommendations, scoped by the active mode.
    private var listedPapers: [Paper] {
        var result = papersForTopic.filter(matchesSearch)
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
            ToolbarItem(placement: .status) {
                modePicker
            }
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, placeholder: L10n.pick("Search papers...", "搜索文献…"))
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
        .sheet(isPresented: $showAddSheet) {
            AddPaperView(topicName: topic.name) { papers in
                _ = store.addOrUpdate(papers: papers)
            }
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
            List(selection: listSelection) {
                if !recommendedPapers.isEmpty {
                    paperSection(
                        title: L10n.pick("Daily Recommendations", "每日推荐"),
                        systemImage: "sparkles",
                        color: .orange,
                        papers: recommendedPapers,
                        showReason: true
                    )
                }
                paperSection(
                    title: mode == .all ? L10n.pick("Papers", "文献") : mode.title,
                    systemImage: mode == .all ? "doc.text" : (mode.status?.iconName ?? "doc.text"),
                    color: .accentColor,
                    papers: listedPapers,
                    showReason: false
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var listSelection: Binding<Set<String>> {
        Binding(
            get: { selectedPaper.map { Set([$0.id]) } ?? [] },
            set: { ids in
                if let id = ids.first {
                    withAnimation(detailPaneAnimation) {
                        selectedPaper = papersForTopic.first { $0.id == id }
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func paperSection(title: String, systemImage: String, color: Color,
                              papers: [Paper], showReason: Bool) -> some View {
        if !papers.isEmpty {
            sectionHeader(title: title, systemImage: systemImage, count: papers.count, color: color)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 4, trailing: 14))

            ForEach(papers) { paper in
                PaperRow(paper: paper, isSelected: selectedPaper?.id == paper.id,
                         metadata: metadata, showReason: showReason)
                    .tag(paper.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                    .onTapGesture { toggleSelection(paper) }
            }
        }
    }

    private func sectionHeader(title: String, systemImage: String, count: Int, color: Color) -> some View {
        HStack(spacing: 7) {
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                hasActiveSearch ? L10n.pick("No results", "无结果") : emptyTitle,
                systemImage: hasActiveSearch ? "magnifyingglass" : emptyIcon
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
        if mode == .all {
            return L10n.pick("Use Fetch to pull recent papers, or + to add manually.",
                             "点击拉取获取近期文献，或用 + 手动添加。")
        }
        return L10n.pick("Papers you mark will appear here.", "标记后的文献会显示在这里。")
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        HStack(spacing: 10) {
            SummaryChip(value: papersForTopic.count, label: L10n.pick("Papers", "文献"), systemImage: "doc.text")
            SummaryChip(value: papersForTopic.filter { $0.status == .starred }.count,
                        label: L10n.pick("Starred", "收藏"), systemImage: "star")
            SummaryChip(value: papersForTopic.filter { $0.status == .pending }.count,
                        label: L10n.pick("Pending", "待读"), systemImage: "clock")

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

    private var actionCluster: some View {
        HStack(spacing: 6) {
            sortMenu
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 24)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Add paper", "添加文献"))
        }
    }

    // MARK: - Detail Pane

    private func detailPane(for paper: Paper) -> some View {
        FacetSidebarPane(
            title: L10n.pick("Paper", "文献"),
            systemImage: "doc.text",
            subtitle: paper.title,
            onClose: {
                withAnimation(detailPaneAnimation) { selectedPaper = nil }
            }
        ) {
            PaperDetailPane(paper: paper)
        }
    }

    // MARK: - Toolbar

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Text(m.title).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .help(L10n.pick("Filter papers", "筛选文献"))
    }

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
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                )
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
        store.clearRecommendations(paperIds: pool.map(\.id))
        let fresh = papersForTopic
        let engine = RecommendEngine(config: ConfigManager.shared.effectiveConfig)
        let results = engine.recommend(papers: fresh)
        for result in results {
            store.setPaperRecommended(id: result.paper.id, isRecommended: true, reason: result.reason)
        }
        withAnimation(detailPaneAnimation) { mode = .all }
        isRecommending = false
        toast.show(L10n.pick("Recommended \(results.count) papers", "已推荐 \(results.count) 篇"),
                   type: .success, duration: 2)
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
}
