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
                toolbarActions
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

    private var toolbarActions: some View {
        HStack(spacing: 4) {
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
}
