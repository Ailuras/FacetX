import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var windowOpener = MainWindowOpener.shared
    @State private var workflows = PaperWorkflowService.shared
    private var settings = AppSettings.shared

    // Filter and Sort states
    @State private var selectedSidebarItem: SidebarItem? = .recommended
    @State private var selectedCollectionIds: Set<String> = []
    @State private var searchKeyword: String = ""
    /// Debounced mirror of `searchKeyword` — drives the actual filtering so a
    /// burst of keystrokes triggers at most one `applyFilters` pass.
    @State private var debouncedSearch: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    // Topic is single-select; Fields/Tier are multi-select (in the toolbar
    // filter popover). Union within a group, intersect across groups.
    @State private var selectedTopic: String?
    @State private var selectedFields: Set<String> = []
    @State private var selectedTiers: Set<Int> = []
    @State private var includedTags: Set<String> = []
    @State private var excludedTags: Set<String> = []
    @State private var showFilters = false
    @State private var showSortOptions = false

    // Selection state
    /// Multi-selection of paper IDs (⌘/⇧ click). count==1 drives the detail view.
    @State private var selectedPaperIds: Set<String> = []
    /// Last paper actually opened; retained when the list selection clears.
    @State private var lastViewedPaperId: String?
    /// Bumped by the Add Tag command to ask the detail view to open its prompt.
    @State private var addTagSignal: Int = 0

    // Async execution states
    @State private var showImport: Bool = false
    @State private var isTranslating: Bool = false
    /// Paper IDs currently resolving their PDF; per-paper so switching detail
    /// views does not carry the spinner state across papers.
    @State private var resolvingPdfIds: Set<String> = []

    // Cached filtered results — recalculated only when inputs change.
    @State private var filteredPapers: [Paper] = []

    /// Aggregates all filter inputs into a single hashable value so `.onChange`
    /// can watch one expression instead of chaining many.
    private var filterInputs: FilterInputs {
        FilterInputs(
            paperCount: store.papers.count,
            paperVersion: store.paperVersion,
            settingsVersion: settings.configVersion,
            metadataVersion: metadata.metadataVersion,
            sidebarItem: selectedSidebarItem,
            collectionIds: selectedCollectionIds,
            topic: selectedTopic,
            includedTags: includedTags,
            excludedTags: excludedTags,
            fields: selectedFields,
            tiers: selectedTiers,
            search: debouncedSearch
        )
    }

    private struct FilterInputs: Equatable {
        var paperCount: Int
        var paperVersion: Int
        var settingsVersion: Int
        var metadataVersion: Int
        var sidebarItem: SidebarItem?
        var collectionIds: Set<String>
        var topic: String?
        var includedTags: Set<String>
        var excludedTags: Set<String>
        var fields: Set<String>
        var tiers: Set<Int>
        var search: String
    }

    /// The paper whose details are shown. Driven by `lastViewedPaperId` (not the
    /// live list selection) so clicking empty space in the list — which clears
    /// the selection — keeps the last opened paper's details visible.
    var selectedPaper: Paper? {
        guard let id = lastViewedPaperId else { return nil }
        return store.papers.first(where: { $0.id == id })
    }

    /// Papers currently multi-selected, in list order.
    private var selectedPapers: [Paper] {
        filteredPapers.filter { selectedPaperIds.contains($0.id) }
    }

    private var selectedPaperIndex: Int? {
        guard let id = lastViewedPaperId else { return nil }
        return filteredPapers.firstIndex(where: { $0.id == id })
    }

    private var canGoPrevious: Bool { selectedPaperIndex.map { $0 > 0 } ?? false }
    private var canGoNext: Bool {
        selectedPaperIndex.map { $0 < filteredPapers.count - 1 } ?? false
    }

    // MARK: - Toolbar helpers (unified; used for both list and detail groups)

    private var filtersActive: Bool { !selectedFields.isEmpty || !selectedTiers.isEmpty }

    /// Active sort dimension, resolved from the persisted setting.
    private var sortKey: SortKey { SortKey(rawValue: settings.sortKeyRaw) ?? .score }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    @ViewBuilder
    private func toolbarIcon(_ systemName: String,
                             isActive: Bool = false,
                             isEnabled: Bool = true,
                             activeColor: Color = .accentColor) -> some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(activeColor.opacity(0.80))
                    .frame(width: 18, height: 18)
            }
            Image(systemName: systemName)
                .font(.system(size: 9.5, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isActive  ? Color.white :
                    isEnabled ? Color.primary.opacity(0.72) :
                                Color.primary.opacity(0.26)
                )
        }
        .frame(width: 23, height: 23)
        .contentShape(Circle())
    }

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters").font(.headline)
                Spacer()
                Button("Clear") { selectedFields = []; selectedTiers = [] }
                    .controlSize(.small)
                    .disabled(!filtersActive)
            }
            if !metadata.allFields.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIELDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(metadata.allFields, id: \.self) { field in
                        FilterRow(title: field, colorKey: "field:\(field)",
                                  defaultColor: .teal,
                                  isSelected: selectedFields.contains(field)) {
                            toggle(field, in: &selectedFields)
                        }
                    }
                }
            }
            if !metadata.allTiers.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("TIER").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(metadata.allTiers, id: \.self) { tier in
                        FilterRow(title: "Tier \(tier)", colorKey: "tier:\(tier)",
                                  defaultColor: MetadataStore.tierDefaultColor(tier),
                                  isSelected: selectedTiers.contains(tier)) {
                            toggle(tier, in: &selectedTiers)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 230)
    }

    private var sortPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.pick("Sort by", "排序方式"))
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(SortKey.allCases) { key in
                Button {
                    settings.sortKeyRaw = key.rawValue
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: key.systemImage)
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(key.title)
                        Spacer()
                        if sortKey == key {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }

            Divider().padding(.vertical, 4)

            Button {
                settings.sortAscending.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: settings.sortAscending ? "arrow.up" : "arrow.down")
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    Text(settings.sortAscending ? L10n.pick("Ascending", "升序") : L10n.pick("Descending", "降序"))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)
        }
        .padding(14)
        .frame(width: 200)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedItem: $selectedSidebarItem,
                selectedCollectionIds: $selectedCollectionIds,
                selectedTopic: $selectedTopic,
                includedTags: $includedTags,
                excludedTags: $excludedTags,
                tags: store.allTags,
                collections: store.allCollections,
                metadata: metadata,
                papers: store.papers
            )
        } content: {
            PaperListView(
                papers: filteredPapers,
                selectedPaperIds: $selectedPaperIds,
                metadata: metadata,
                highlightsDailyRecommendations: selectedSidebarItem == .recommended && selectedCollectionIds.isEmpty,
                showsStatusMarker: (selectedSidebarItem == .recommended || selectedSidebarItem == .all) && selectedCollectionIds.isEmpty,
                onCancelRecommendation: cancelRecommendation,
                onSelectionChange: handleSelectionChange,
                onCopyBibtex: copyBibtex,
                onUpdatePaper: updatePaper,
                onDeletePaper: confirmDelete,
                onSetStatus: setStatus,
                onAddToCollection: addToCollection,
                collections: store.allCollections
            )
        } detail: {
            if selectedPaperIds.count > 1 {
                BatchActionsView(
                    papers: selectedPapers,
                    collections: store.allCollections,
                    onCopyBibtex: { copyBibtex(selectedPapers) },
                    onSetStatus: { setStatus(selectedPapers, $0) },
                    onAddToCollection: { addToCollection(selectedPapers, $0) },
                    onAddTag: { requestAddTag(selectedPapers) },
                    onUpdate: { updatePaper(selectedPapers) },
                    onDelete: { confirmDelete(selectedPapers) }
                )
            } else if let paper = selectedPaper {
                PaperDetailView(
                    paper: paper,
                    isTranslating: $isTranslating,
                    resolvingPdfIds: $resolvingPdfIds,
                    onTranslate: translate,
                    onFetchPdf: fetchPdf,
                    onRevealPdf: revealPdf,
                    onSetPdf: setPdf,
                    onDropPdf: dropPdf,
                    onRemovePdf: removePdf,
                    onStatusChange: updatePaperStatus,
                    onAddTag: addPaperTag,
                    onRemoveTag: removePaperTag,
                    onAddToCollection: addPaperToCollection,
                    onRemoveFromCollection: removePaperFromCollection,
                    addTagSignal: addTagSignal
                )
            } else {
                EmptyDetailView()
            }
        }
        .onAppear {
            applyFilters()
            focusRequestedPaper()
        }
        .onChange(of: filterInputs) { applyFilters() }
        .onChange(of: searchKeyword) { _, new in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                debouncedSearch = new
            }
        }
        .onChange(of: windowOpener.requestedPaperId) { focusRequestedPaper() }
        .onChange(of: selectedSidebarItem) { _, new in
            if new != nil { selectedCollectionIds.removeAll() }
        }
        .searchable(text: $searchKeyword, placement: .toolbar, prompt: "Search title, abstract or authors...")
        .toolbar {
            // ── List operations ────────────────────────────────────────────
            ToolbarItem(placement: .automatic) {
                ControlGroup {
                    Button(action: fetchPapers) {
                        if workflows.isFetching {
                            ProgressView().controlSize(.small).frame(width: 22, height: 22)
                        } else {
                            toolbarIcon("arrow.clockwise")
                        }
                    }
                    .disabled(workflows.isBusy)
                    .accessibilityLabel("Fetch new papers")
                    .help("Fetch new papers from OpenAlex")

                    Button(action: recommendPapers) {
                        if workflows.isRecommending {
                            ProgressView().controlSize(.small).frame(width: 22, height: 22)
                        } else {
                            toolbarIcon("wand.and.stars")
                        }
                    }
                    .disabled(workflows.isBusy)
                    .accessibilityLabel("Generate recommendations")
                    .help("Generate daily paper recommendations")

                    Button { showImport = true } label: {
                        toolbarIcon("plus")
                    }
                    .accessibilityLabel("Add paper")
                    .help("Add a paper by DOI, title search, or manual entry")
                    .sheet(isPresented: $showImport) {
                        PaperImportView { paper in
                            _ = store.addOrUpdate(papers: [paper])
                            applyFilters()
                            NotificationCenter.shared.showToast(
                                "Added \"\(paper.title)\"",
                                type: .success
                            )
                        }
                    }

                    Button { showFilters.toggle() } label: {
                        toolbarIcon("line.3.horizontal.decrease", isActive: filtersActive)
                    }
                    .accessibilityLabel("Filter papers")
                    .help("Filter by field and tier")
                    .popover(isPresented: $showFilters, arrowEdge: .bottom) { filterPopover }

                    Button { showSortOptions.toggle() } label: {
                        toolbarIcon("arrow.up.arrow.down", isActive: showSortOptions)
                    }
                    .accessibilityLabel("Sort papers")
                    .help("Sort papers")
                    .popover(isPresented: $showSortOptions, arrowEdge: .bottom) { sortPopover }
                }
                .fixedSize()
            }

            // ── Detail navigation + status (always visible; disabled when nothing is open) ──
            // `paper` is resolved once here — avoids repeated O(n) scans inside ForEach.
            ToolbarItem(placement: .automatic) {
                let paper = selectedPaper
                ControlGroup {
                    Button(action: selectPreviousPaper) {
                        toolbarIcon("chevron.left", isEnabled: canGoPrevious)
                    }
                    .disabled(!canGoPrevious)
                    .help("Previous paper")

                    ForEach(PaperStatus.allCases, id: \.self) { status in
                        let isActive = paper?.status == status
                        Button {
                            if let paper { updatePaperStatus(paper, status: status) }
                        } label: {
                            toolbarIcon(status.iconName,
                                       isActive: isActive,
                                       isEnabled: paper != nil,
                                       activeColor: status.iconColor)
                        }
                        .disabled(paper == nil)
                        .help(status.displayName)
                    }

                    Button(action: selectNextPaper) {
                        toolbarIcon("chevron.right", isEnabled: canGoNext)
                    }
                    .disabled(!canGoNext)
                    .help("Next paper")
                }
                .fixedSize()
            }
        }
        // Publish the runnable actions to the menu-bar commands (AppCommands).
        .focusedSceneValue(\.paperActions, paperActions)
    }

    /// Snapshot of menu-bar command actions for the current state. Optional
    /// closures encode disabled state; `selectedSidebarItem`'s own `.onChange`
    /// clears the collection selection. Kept out of `body` so the type-checker
    /// doesn't have to solve these closures inside the view tree.
    private var paperActions: PaperActions {
        let busy = workflows.isBusy
        let selectView: (SidebarItem) -> Void = { selectedSidebarItem = $0 }
        let selectPrevious: (() -> Void)? = canGoPrevious ? { selectPreviousPaper() } : nil
        let selectNext: (() -> Void)? = canGoNext ? { selectNextPaper() } : nil
        let setStatus: ((PaperStatus) -> Void)? = selectedPaper.map { paper in
            { updatePaperStatus(paper, status: $0) }
        }
        let addTag: (() -> Void)? = selectedPaper == nil ? nil : { addTagSignal += 1 }
        let fetch: (() -> Void)? = busy ? nil : { fetchPapers() }
        let recommend: (() -> Void)? = busy ? nil : { recommendPapers() }
        let copyBibtex: (() -> Void)? = selectedPaper.map { paper in
            { self.copyBibtex([paper]) }
        }
        let openLink: (() -> Void)? = selectedPaper.flatMap { paper in
            paperLinkURL(paper).map { url in
                { NSWorkspace.shared.open(url) }
            }
        }
        let hasAnyFilter =
            selectedTopic != nil ||
            !selectedFields.isEmpty ||
            !selectedTiers.isEmpty ||
            !includedTags.isEmpty ||
            !excludedTags.isEmpty ||
            !searchKeyword.isEmpty
        let clearFilters: (() -> Void)? = hasAnyFilter ? { resetFilters() } : nil
        let exportBib: (() -> Void)? = filteredPapers.isEmpty ? nil : { exportBibliography() }
        let hasPending = store.papers.contains(where: { $0.status == .pending })
        let surprise: (() -> Void)? = hasPending ? { surpriseMe() } : nil
        let translate: (() -> Void)? = (selectedPaper?.abstract.isEmpty == false && !isTranslating)
            ? { if let p = selectedPaper { self.translate(paper: p) } }
            : nil
        return PaperActions(
            selectView: selectView,
            selectPrevious: selectPrevious,
            selectNext: selectNext,
            setStatus: setStatus,
            addTag: addTag,
            fetch: fetch,
            recommend: recommend,
            copyBibtex: copyBibtex,
            openLink: openLink,
            clearFilters: clearFilters,
            exportBibliography: exportBib,
            surpriseMe: surprise,
            translateAbstract: translate
        )
    }

    /// Pick a random pending paper and jump to it. Clears filters first so
    /// the selection always lands; the Pending sidebar tab becomes active.
    private func surpriseMe() {
        let pending = store.papers.filter { $0.status == .pending }
        guard let pick = pending.randomElement() else {
            NotificationCenter.shared.showToast(L10n.t(.surpriseEmpty), type: .warning)
            return
        }
        resetFiltersSilently()
        selectedCollectionIds = []
        selectedSidebarItem = .pending
        applyFilters()
        if filteredPapers.contains(where: { $0.id == pick.id }) {
            selectedPaperIds = [pick.id]
            lastViewedPaperId = pick.id
        }
    }

    /// Same as `resetFilters` but no toast — used when surprise picking so
    /// the user isn't double-notified.
    private func resetFiltersSilently() {
        selectedTopic = nil
        selectedFields = []
        selectedTiers = []
        includedTags = []
        excludedTags = []
        searchKeyword = ""
        debouncedSearch = ""
    }

    private func exportBibliography() {
        guard !filteredPapers.isEmpty else {
            NotificationCenter.shared.showToast(L10n.t(.exportBibEmpty), type: .warning)
            return
        }

        let panel = NSSavePanel()
        // BibTeX (.bib) and RIS (.ris) aren't registered system UTTypes, so
        // accept all readable file types and infer the format from the chosen
        // extension. .json is registered and lets us also offer that format.
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "vellumx-bibliography.bib"
        panel.message = L10n.pick(
            "Choose .bib (BibTeX), .ris (Zotero/Mendeley), .md (Markdown), or .csv (spreadsheet).",
            "选择 .bib（BibTeX）、.ris（Zotero/Mendeley）、.md（Markdown）或 .csv（电子表格）。"
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let papers = filteredPapers
        let content: String
        switch url.pathExtension.lowercased() {
        case "ris":     content = CitationExporter.ris(for: papers)
        case "md":      content = CitationExporter.markdown(for: papers)
        case "csv":     content = CitationExporter.csv(for: papers)
        default:        content = CitationExporter.bibtex(for: papers)
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            NotificationCenter.shared.showToast(
                "\(L10n.t(.exportBibSuccess)) — \(papers.count) → \(url.lastPathComponent)",
                type: .success
            )
        } catch {
            NotificationCenter.shared.showToast(
                "\(L10n.t(.exportBibFailed)): \(error.localizedDescription)",
                type: .error
            )
        }
    }

    private func resetFilters() {
        selectedTopic = nil
        selectedFields = []
        selectedTiers = []
        includedTags = []
        excludedTags = []
        searchKeyword = ""
        debouncedSearch = ""
        NotificationCenter.shared.showToast(L10n.t(.clearFiltersToast), type: .success)
    }

    /// Best clickable destination for a paper: DOI URL if known, else the
    /// landing page from OpenAlex. Returns `nil` when neither is usable.
    private func paperLinkURL(_ paper: Paper) -> URL? {
        if let doi = paper.doi {
            let bare = PdfResolver.stripDoiPrefix(doi)
            if !bare.isEmpty, let url = URL(string: "https://doi.org/\(bare)") {
                return url
            }
        }
        let landing = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return landing.isEmpty ? nil : URL(string: landing)
    }

    /// Reveal and select a paper requested from outside the window (e.g. the
    /// menu bar's "Open in VellumX"). Switches to a sidebar tab that contains
    /// the paper so the list selection lands, then opens its detail.
    private func focusRequestedPaper() {
        guard let id = windowOpener.requestedPaperId,
              let paper = store.papers.first(where: { $0.id == id }) else { return }

        selectedTopic = nil
        selectedFields = []
        selectedTiers = []
        searchKeyword = ""
        debouncedSearch = ""

        // If the paper belongs to any collection, switch to the first one.
        if let firstCollectionId = paper.collectionIds.first,
           store.allCollections.contains(where: { $0.id == firstCollectionId }) {
            selectedCollectionIds = [firstCollectionId]
            selectedSidebarItem = nil
        } else {
            selectedCollectionIds = []
            selectedSidebarItem = sidebarItem(for: paper)
        }

        applyFilters()
        selectedPaperIds = [id]
        lastViewedPaperId = id
        windowOpener.requestedPaperId = nil
    }

    private func sidebarItem(for paper: Paper) -> SidebarItem {
        if paper.isRecommended,
           let recommendedAt = paper.recommendedAt,
           Calendar.current.isDateInToday(recommendedAt) {
            return .recommended
        }

        switch paper.status {
        case .pending:  return .pending
        case .starred:  return .starred
        case .read:     return .read
        case .skip:     return .skipped
        }
    }

    // MARK: - Filtering

    private func applyFilters() {
        var result = store.papers

        // 0. Collection view takes priority over sidebar status. A parent folder
        //    stands in for its whole subtree, so include descendants' papers too.
        //    With several folders selected, show the union of their subtrees.
        if !selectedCollectionIds.isEmpty {
            var subtree: Set<String> = []
            for id in selectedCollectionIds {
                subtree.formUnion(store.collectionSubtreeIds(id))
            }
            result = result.filter { paper in paper.collectionIds.contains(where: subtree.contains) }
        }

        // 1. Filter by Sidebar selection
        else if let selected = selectedSidebarItem {
            switch selected {
            case .all:
                break
            case .recommended:
                result = result.filter { $0.isRecommended }
            case .pending:
                result = result.filter { $0.status == .pending }
            case .starred:
                result = result.filter { $0.status == .starred }
            case .read:
                result = result.filter { $0.status == .read }
            case .skipped:
                result = result.filter { $0.status == .skip }
            }
        }

        // 1b. Taxonomy filters (multi-select): union within a group, intersect
        // across groups. An empty group doesn't filter.
        if let topic = selectedTopic {
            result = result.filter { paper in
                paper.track.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .contains(topic)
            }
        }
        if !selectedFields.isEmpty {
            result = result.filter { paper in
                selectedFields.contains(metadata.field(forAbbr: paper.venueAbbr))
            }
        }
        if !selectedTiers.isEmpty {
            result = result.filter { selectedTiers.contains($0.tier) }
        }
        if !includedTags.isEmpty {
            result = result.filter { paper in
                !includedTags.isDisjoint(with: Set(paper.tags))
            }
        }
        if !excludedTags.isEmpty {
            result = result.filter { paper in
                excludedTags.isDisjoint(with: Set(paper.tags))
            }
        }

        // 2. Filter by search keyword. Tokens are AND-matched against each
        // paper's cached lowercased `searchText` (title, abstract, authors,
        // venue, tags, note) — no per-keystroke re-lowercasing of abstracts.
        let tokens = debouncedSearch.lowercased().split(separator: " ").map(String.init)
        if !tokens.isEmpty {
            result = result.filter { paper in
                let hay = paper.searchText
                return tokens.allSatisfy { hay.contains($0) }
            }
        }

        // 3. Sort. Each key defines a "descending / natural" comparator; the
        //    direction toggle flips it by swapping operands. In the Recommended
        //    view, today's picks stay pinned on top, sorted within each group.
        let ascending = settings.sortAscending
        let ordered: (Paper, Paper) -> Bool = { a, b in
            let lhs = ascending ? b : a
            let rhs = ascending ? a : b
            return Self.precedes(lhs, rhs, by: self.sortKey)
        }
        if selectedSidebarItem == .recommended {
            result.sort {
                let lhsToday = $0.recommendedAt.map { Calendar.current.isDateInToday($0) } ?? false
                let rhsToday = $1.recommendedAt.map { Calendar.current.isDateInToday($0) } ?? false
                if lhsToday != rhsToday { return lhsToday }
                return ordered($0, $1)
            }
        } else {
            result.sort(by: ordered)
        }

        filteredPapers = result
    }

    /// Natural (descending) ordering for a sort key: higher score / more
    /// citations / newer dates first; title A→Z. The caller applies direction.
    private static func precedes(_ a: Paper, _ b: Paper, by key: SortKey) -> Bool {
        switch key {
        case .score:
            if a.score != b.score { return a.score > b.score }
            return a.citedByCount > b.citedByCount
        case .publicationDate:
            return a.publicationDate > b.publicationDate
        case .citations:
            return a.citedByCount > b.citedByCount
        case .statusTime:
            return (a.statusChangedAt ?? .distantPast) > (b.statusChangedAt ?? .distantPast)
        case .dateAdded:
            return (a.addedAt ?? .distantPast) > (b.addedAt ?? .distantPast)
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private func selectPaper(at index: Int) {
        guard filteredPapers.indices.contains(index) else { return }
        let id = filteredPapers[index].id
        selectedPaperIds = [id]
        lastViewedPaperId = id
    }

    private func selectPreviousPaper() {
        guard let index = selectedPaperIndex, index > 0 else { return }
        selectPaper(at: index - 1)
    }

    private func selectNextPaper() {
        guard let index = selectedPaperIndex, index < filteredPapers.count - 1 else { return }
        selectPaper(at: index + 1)
    }

    // MARK: - Actions

    private func updatePaperStatus(_ paper: Paper, status: PaperStatus) {
        let oldIndex = selectedPaperIndex
        let nextId = oldIndex.flatMap { index in
            filteredPapers.indices.contains(index + 1) ? filteredPapers[index + 1].id : nil
        }
        let shouldAdvance = statusListItem(selectedSidebarItem) != nil

        PaperStore.shared.setPaperStatus(id: paper.id, status: status)
        // Always rebuild so the row reflects the new status immediately (the
        // Paper is a class; mutating it in place doesn't re-render rows on its
        // own). Advancing selection only applies in status-filtered views.
        applyFilters()

        guard shouldAdvance,
              let selectedSidebarItem,
              !paperMatches(sidebarItem: selectedSidebarItem, status: status) else { return }

        if let nextId, filteredPapers.contains(where: { $0.id == nextId }) {
            selectedPaperIds = [nextId]
            lastViewedPaperId = nextId
        } else {
            selectedPaperIds = []
            lastViewedPaperId = nil
        }
    }

    private func statusListItem(_ item: SidebarItem?) -> PaperStatus? {
        switch item {
        case .pending: return .pending
        case .starred: return .starred
        case .read: return .read
        case .skipped: return .skip
        default: return nil
        }
    }

    private func paperMatches(sidebarItem: SidebarItem, status: PaperStatus) -> Bool {
        statusListItem(sidebarItem) == status
    }

    private func cancelRecommendation(_ paper: Paper) {
        store.setPaperRecommended(id: paper.id, isRecommended: false)
        applyFilters()
    }

    /// When exactly one row is selected, open it in the detail pane. Multi- or
    /// zero-selection leaves `lastViewedPaperId` so the detail pane can show the
    /// batch placeholder or keep the last opened paper.
    private func handleSelectionChange(_ ids: Set<String>) {
        if ids.count == 1, let id = ids.first {
            lastViewedPaperId = id
        }
    }

    private func copyBibtex(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(CitationExporter.bibtex(for: papers), forType: .string)
        NotificationCenter.shared.showToast(
            papers.count == 1
                ? L10n.t(.copiedBibtex)
                : "Copied \(papers.count) BibTeX entries",
            type: .success
        )
    }

    private func confirmDelete(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let title = papers.count == 1
            ? L10n.t(.deleteConfirmTitle)
            : (AppSettings.shared.language == "zh"
                ? "删除选中的 \(papers.count) 篇论文？"
                : "Delete \(papers.count) papers?")
        NotificationCenter.shared.present(AlertItem(
            title: title,
            message: L10n.t(.deleteConfirmMessage),
            actions: [
                .confirm(L10n.t(.delete), isDestructive: true, action: { deletePapers(papers) }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: nil, textFieldLabel: nil
        ))
    }

    private func deletePapers(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let ids = Set(papers.map(\.id))
        let removedOpen = lastViewedPaperId.map(ids.contains) ?? false
        store.deletePapers(ids: Array(ids))
        selectedPaperIds.subtract(ids)
        applyFilters()
        if removedOpen { lastViewedPaperId = nil }
    }

    /// Refresh papers' metadata from OpenAlex, keeping all user state.
    private func updatePaper(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        // Preserve each paper's track: fetchWorksByIds parses with track "",
        // and addOrUpdate's replaceTopics would otherwise wipe their topics.
        let trackById = Dictionary(papers.map { ($0.id, $0.track) }, uniquingKeysWith: { a, _ in a })
        NotificationCenter.shared.setStatus(
            papers.count == 1
                ? "Updating from OpenAlex..."
                : "Updating \(papers.count) papers from OpenAlex...",
            type: .progress
        )

        Task {
            let fetcher = OpenAlexFetcher(
                config: ConfigManager.shared.effectiveConfig,
                venues: metadata.venues
            )
            let refreshed = await fetcher.fetchWorksByIds(papers.map(\.id))
            guard !refreshed.isEmpty else {
                NotificationCenter.shared.setStatus("Update failed — no result from OpenAlex.", type: .error)
                return
            }
            for r in refreshed { r.track = trackById[r.id] ?? r.track }
            _ = store.addOrUpdate(papers: refreshed)
            applyFilters()
            NotificationCenter.shared.showToast(
                refreshed.count == 1
                    ? "Updated \"\(refreshed[0].title)\""
                    : "Updated \(refreshed.count) papers",
                type: .success
            )
            NotificationCenter.shared.clearStatus()
        }
    }

    // MARK: - Batch actions (operate on a set of papers)

    private func setStatus(_ papers: [Paper], _ status: PaperStatus) {
        for paper in papers { store.setPaperStatus(id: paper.id, status: status) }
        applyFilters()
    }

    private func addToCollection(_ papers: [Paper], _ collectionId: String) {
        for paper in papers { store.addPaperToCollection(paperId: paper.id, collectionId: collectionId) }
        applyFilters()
    }

    private func addTag(_ papers: [Paper], _ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for paper in papers { store.addPaperTag(id: paper.id, tag: trimmed) }
        applyFilters()
    }

    private func requestAddTag(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        NotificationCenter.shared.present(AlertItem(
            title: L10n.t(.cmdAddTag),
            message: nil,
            actions: [
                .confirm(L10n.t(.cmdAddTag), action: {
                    let tag = NotificationCenter.shared.currentAlert?.textFieldValue ?? ""
                    addTag(papers, tag)
                }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: "",
            textFieldLabel: "Tag"
        ))
    }

    private func addPaperTag(_ paper: Paper, tag: String) {
        store.addPaperTag(id: paper.id, tag: tag)
        applyFilters()
    }

    private func removePaperTag(_ paper: Paper, tag: String) {
        store.removePaperTag(id: paper.id, tag: tag)
        applyFilters()
    }

    private func addPaperToCollection(_ paper: Paper, collectionId: String) {
        store.addPaperToCollection(paperId: paper.id, collectionId: collectionId)
        applyFilters()
    }

    private func removePaperFromCollection(_ paper: Paper, collectionId: String) {
        store.removePaperFromCollection(paperId: paper.id, collectionId: collectionId)
        applyFilters()
    }

    private func fetchPapers() {
        guard !ConfigManager.shared.effectiveConfig.tracks.isEmpty else {
            NotificationCenter.shared.setStatus("No tracks configured - add one in Settings > Rules", type: .error)
            return
        }
        // Fetching contacts OpenAlex and can be slow; confirm before running.
        NotificationCenter.shared.present(AlertItem(
            title: L10n.t(.fetchConfirmTitle),
            message: L10n.t(.fetchConfirmMessage),
            actions: [
                .confirm(L10n.t(.cmdFetch), action: {
                    Task { _ = await workflows.fetchPapers() }
                }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: nil, textFieldLabel: nil
        ))
    }

    private func recommendPapers() {
        Task { _ = await workflows.recommendPapers() }
    }

    private func translate(paper: Paper) {
        guard settings.translateEnabled else {
            NotificationCenter.shared.showToast("Translation is disabled — enable it in Settings ▸ API", type: .warning)
            return
        }
        guard !paper.abstract.isEmpty else {
            NotificationCenter.shared.showToast("No abstract available to translate", type: .warning)
            return
        }
        isTranslating = true
        let provider = ConfigManager.shared.effectiveConfig.translate.provider
        NotificationCenter.shared.setStatus("Translating abstract via \(provider.displayName)...", type: .progress)
        let config = ConfigManager.shared.effectiveConfig

        Task {
            do {
                let translator = TranslationService(config: config, apiKey: settings.apiKey)
                let abstractZh = try await translator.translateAbstract(
                    id: paper.id,
                    abstract: paper.abstract,
                    cachedAbstractZh: paper.abstractZh
                )
                paper.abstractZh = abstractZh
                PaperStore.shared.setPaperTranslation(id: paper.id, abstractZh: abstractZh)
                NotificationCenter.shared.showToast("Abstract translated successfully!", type: .success)
                NotificationCenter.shared.clearStatus()
            } catch {
                NotificationCenter.shared.showToast("Translation failed: \(error.localizedDescription)", type: .error)
                NotificationCenter.shared.clearStatus()
            }
            isTranslating = false
        }
    }

    private func fetchPdf(for paper: Paper) {
        resolvingPdfIds.insert(paper.id)
        Task {
            await PdfCoordinator.fetch(paper: paper, store: store)
            resolvingPdfIds.remove(paper.id)
        }
    }

    private func revealPdf(for paper: Paper) {
        Task { await PdfCoordinator.reveal(paper: paper, store: store) }
    }

    private func setPdf(for paper: Paper) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        panel.prompt = L10n.t(.choosePdf)
        if panel.runModal() == .OK, let url = panel.url {
            PdfCoordinator.setManualPdf(paper: paper, store: store, from: url)
        }
    }

    private func dropPdf(id: String, url: URL) {
        guard let paper = store.papers.first(where: { $0.id == id }) else {
            NotificationCenter.shared.showToast(L10n.t(.paperNotFound), type: .warning)
            return
        }
        PdfCoordinator.setManualPdf(paper: paper, store: store, from: url)
    }

    private func removePdf(for paper: Paper) {
        PdfCoordinator.removePdf(paper: paper, store: store)
    }
}

// MARK: - Batch actions panel (shown when >1 paper is selected)

private struct BatchActionsView: View {
    let papers: [Paper]
    let collections: [PaperCollection]
    let onCopyBibtex: () -> Void
    let onSetStatus: (PaperStatus) -> Void
    let onAddToCollection: (String) -> Void
    let onAddTag: () -> Void
    let onUpdate: () -> Void
    let onDelete: () -> Void

    @State private var showStatus = false
    @State private var showCollection = false

    private let panelWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            header
            actions
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: "checklist")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text("\(papers.count) \(L10n.t(.batchSelected))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            pillButton(L10n.t(.cite), "doc.on.doc", action: onCopyBibtex)

            pillButton(L10n.t(.cmdSetStatus), "flag", chevron: true) { showStatus = true }
                .popover(isPresented: $showStatus, arrowEdge: .trailing) {
                    popoverList {
                        ForEach(PaperStatus.allCases, id: \.self) { status in
                            popoverRow(status.displayName, status.iconName) {
                                onSetStatus(status)
                                showStatus = false
                            }
                        }
                    }
                }

            if !collections.isEmpty {
                pillButton(L10n.t(.cmdAddToCollection), "folder", chevron: true) { showCollection = true }
                    .popover(isPresented: $showCollection, arrowEdge: .trailing) {
                        popoverList {
                            ForEach(collections) { collection in
                                popoverRow(collection.name, collection.icon ?? "folder") {
                                    onAddToCollection(collection.id)
                                    showCollection = false
                                }
                            }
                        }
                    }
            }

            pillButton(L10n.t(.cmdAddTag), "tag", action: onAddTag)
            pillButton(L10n.t(.cmdUpdatePaper), "arrow.clockwise", action: onUpdate)

            Divider().padding(.vertical, 4)

            pillButton(L10n.t(.cmdDeletePaper), "trash", role: .destructive, action: onDelete)
        }
        .frame(width: panelWidth)
    }

    private func pillButton(_ title: String, _ icon: String,
                            role: ButtonRole? = nil,
                            chevron: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .overlay(alignment: .trailing) {
                    if chevron {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .buttonStyle(BatchPillButtonStyle(destructive: role == .destructive))
    }

    private func popoverList<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) { content() }
            .padding(6)
            .frame(minWidth: 170)
    }

    private func popoverRow(_ title: String, _ icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width pill button used in the batch actions panel, with hover and
/// pressed feedback so every row (including the popover triggers) matches.
private struct BatchPillButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, destructive: destructive)
    }

    private struct Pill: View {
        let configuration: ButtonStyle.Configuration
        let destructive: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(
                            configuration.isPressed ? 0.16 : (hovering ? 0.11 : 0.07)
                        ))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
