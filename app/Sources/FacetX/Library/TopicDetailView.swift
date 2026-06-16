import SwiftUI

struct TopicDetailView: View {
    let topic: TrackPref

    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var settings = LibrarySettings.shared

    @State private var searchText = ""
    @State private var selectedPaper: Paper?
    @State private var sortKey: SortKey = .score
    @State private var showAddSheet = false
    @State private var isRecommending = false
    @State private var isFetching = false

    private let detailPaneAnimation = FacetTheme.detailSpring

    private var papersForTopic: [Paper] {
        store.papers.filter { paper in
            let topics = paper.track.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return topics.contains(topic.name)
        }
    }

    private var filteredPapers: [Paper] {
        var result = papersForTopic

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let tokens = searchText.lowercased().split(separator: " ").map(String.init)
            result = result.filter { paper in
                tokens.allSatisfy { paper.searchText.contains($0) }
            }
        }

        let ascending = settings.sortAscending
        switch sortKey {
        case .score:
            result.sort { ascending ? $0.score < $1.score : $0.score > $1.score }
        case .publicationDate:
            result.sort { ascending ? $0.publicationDate < $1.publicationDate : $0.publicationDate > $1.publicationDate }
        case .citations:
            result.sort { ascending ? $0.citedByCount < $1.citedByCount : $0.citedByCount > $1.citedByCount }
        case .statusTime:
            result.sort { lhs, rhs in
                let l = lhs.statusChangedAt ?? .distantPast
                let r = rhs.statusChangedAt ?? .distantPast
                return ascending ? l < r : l > r
            }
        case .dateAdded:
            result.sort { lhs, rhs in
                let l = lhs.addedAt ?? .distantPast
                let r = rhs.addedAt ?? .distantPast
                return ascending ? l < r : l > r
            }
        case .title:
            result.sort { lhs, rhs in
                let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                paperList
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
                ToolbarSearchField(text: $searchText, placeholder: "Search papers...")
                    .frame(width: 220, height: 24)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 3) {
                    recommendButton
                    fetchButton
                    sortMenu
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .help("Add paper")
                }
            }
        }
        .onChange(of: store.paperVersion) {
            if let paper = selectedPaper,
               !store.papers.contains(where: { $0.id == paper.id }) {
                withAnimation(detailPaneAnimation) {
                    selectedPaper = nil
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPaperView(topicName: topic.name) { papers in
                _ = store.addOrUpdate(papers: papers)
            }
        }
    }

    // MARK: - Paper List

    private var paperList: some View {
        VStack(spacing: 0) {
            infoBar

            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No papers in this topic" : "No results",
                    systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Add papers via the + button in the toolbar."
                        : "No papers match \"\(searchText)\".")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { selectedPaper.map { Set([$0.id]) } ?? [] },
                    set: { ids in
                        if let id = ids.first {
                            withAnimation(detailPaneAnimation) {
                                selectedPaper = filteredPapers.first { $0.id == id }
                            }
                        }
                    }
                )) {
                    ForEach(filteredPapers) { paper in
                        PaperRow(paper: paper, isSelected: selectedPaper?.id == paper.id, metadata: metadata)
                            .tag(paper.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .onTapGesture {
                                if selectedPaper?.id == paper.id {
                                    withAnimation(detailPaneAnimation) {
                                        selectedPaper = nil
                                    }
                                } else {
                                    withAnimation(detailPaneAnimation) {
                                        selectedPaper = paper
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var infoBar: some View {
        HStack(spacing: 12) {
            SummaryChip(value: papersForTopic.count, label: "Papers", systemImage: "doc.text")

            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                FacetInfoBadge(
                    text: "\(filteredPapers.count) results",
                    systemImage: "magnifyingglass",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }

            Spacer()
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    // MARK: - Detail Pane

    private func detailPane(for paper: Paper) -> some View {
        FacetSidebarPane(
            title: "Paper",
            systemImage: "doc.text",
            subtitle: paper.title,
            onClose: {
                withAnimation(detailPaneAnimation) {
                    selectedPaper = nil
                }
            }
        ) {
            PaperDetailPane(paper: paper)
        }
    }

    // MARK: - Toolbar

    @EnvironmentObject private var toast: ToastController

    private var recommendButton: some View {
        Button {
            surpriseMe()
        } label: {
            if isRecommending {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "wand.and.stars")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .disabled(isRecommending)
        .help("Pick a random pending paper")
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
        .help("Fetch new papers from OpenAlex")
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
                        if sortKey == key {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                settings.sortAscending.toggle()
            } label: {
                HStack {
                    Image(systemName: settings.sortAscending ? "arrow.up" : "arrow.down")
                    Text(settings.sortAscending ? "Ascending" : "Descending")
                }
            }
        } label: {
            Image(systemName: sortKey.systemImage)
                .font(.system(size: 12, weight: .medium))
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
        .help("Sort: \(sortKey.title)")
    }

    // MARK: - Actions

    private func surpriseMe() {
        let pending = papersForTopic.filter { $0.status == .pending }
        guard let pick = pending.randomElement() else {
            toast.show("No pending papers in this topic", type: .info, duration: 2)
            return
        }
        withAnimation(detailPaneAnimation) {
            selectedPaper = pick
        }
    }

    private func fetchPapers() {
        guard !topic.query.trimmingCharacters(in: .whitespaces).isEmpty else {
            toast.show("No OpenAlex search query configured for this topic", type: .warning, duration: 2.5)
            return
        }

        isFetching = true

        Task {
            do {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                guard let fromDay = Calendar.current.date(byAdding: .day, value: -45, to: Date()) else { return }
                let fromDate = dateFormatter.string(from: fromDay)
                let toDate = dateFormatter.string(from: Date())

                // Single-topic fetch: use searchPapers logic inline
                var allWorks: [OpenAlexWork] = []
                var cursor: String? = "*"
                let perPage = min(settings.perPage, 100)
                var count = 0
                let maxResults = min(settings.defaultMaxResults, 200)

                while count < maxResults, let c = cursor {
                    var filters = ["from_publication_date:\(fromDate)", "to_publication_date:\(toDate)", "type:article"]
                    if !ConfigManager.shared.effectiveConfig.openalex.topic_filter.isEmpty {
                        filters.append(ConfigManager.shared.effectiveConfig.openalex.topic_filter)
                    }
                    var components = URLComponents(string: ConfigManager.shared.effectiveConfig.openalex.base_url)
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

                let fetcherLocal = OpenAlexFetcher(config: ConfigManager.shared.effectiveConfig, venues: MetadataStore.shared.venues)
                let papers = allWorks.map { fetcherLocal.parseWork($0, track: topic.name) }

                // Apply keyword filtering
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
                toast.show("Fetched \(relevant.count) papers (\(inserted) new, \(updated) updated)", type: .success, duration: 3)
            } catch {
                isFetching = false
                toast.show("Fetch failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
