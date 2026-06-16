import SwiftUI

struct AddPaperView: View {
    let topicName: String
    let onAdd: ([Paper]) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case search = "OpenAlex", manual = "Manual" }
    @State private var tab = Tab.search

    // Search
    @State private var queryText = ""
    @State private var isSearching = false
    @State private var searchResults: [Paper] = []
    @State private var selectedPaperIDs: Set<String> = []

    // Manual
    @State private var title = ""
    @State private var authorsText = ""
    @State private var yearText = ""
    @State private var venue = ""
    @State private var doi = ""
    @State private var url = ""
    @State private var abstract = ""

    private var fetcher: OpenAlexFetcher {
        OpenAlexFetcher(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Group {
                switch tab {
                case .search: searchTab
                case .manual: manualTab
                }
            }
            .frame(minHeight: 300)
        }
        .frame(width: 500)
    }

    private var header: some View {
        HStack {
            Text("Add Paper to \(topicName)").font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if !selectedPaperIDs.isEmpty {
                Button("Add \(selectedPaperIDs.count) Selected") {
                    let papers = searchResults.filter { selectedPaperIDs.contains($0.id) }
                    onAdd(papers)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else if tab == .manual, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add") {
                    addManualPaper()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Search Tab

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("DOI or title...", text: $queryText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }

                Button {
                    search()
                } label: {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(queryText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            if searchResults.isEmpty {
                if isSearching {
                    ProgressView().padding(40)
                } else {
                    Text("Search by DOI or title to find papers from OpenAlex.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(40)
                }
            } else {
                List(selection: $selectedPaperIDs) {
                    ForEach(searchResults) { paper in
                        searchResultRow(paper)
                            .tag(paper.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func searchResultRow(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 8) {
                if !paper.authors.isEmpty {
                    Text(paper.authors.prefix(2).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let year = paper.publicationYear {
                    Text("\(year)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if !paper.venue.isEmpty {
                    Text(paper.venue)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func search() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        searchResults = []
        selectedPaperIDs = []

        Task {
            if trimmed.hasPrefix("10.") || trimmed.contains("doi.org") {
                if let paper = await fetcher.fetchByDOI(trimmed) {
                    paper.track = topicName
                    searchResults = [paper]
                    selectedPaperIDs = [paper.id]
                }
            } else {
                let results = await fetcher.fetchByTitle(trimmed, limit: 10)
                searchResults = results.map { paper in
                    paper.track = topicName
                    return paper
                }
            }
            isSearching = false
        }
    }

    // MARK: - Manual Tab

    private var manualTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title *").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Paper title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Authors").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Author1, Author2", text: $authorsText)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Year").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("2024", text: $yearText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Venue").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Conference or journal", text: $venue)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("DOI").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("10.xxxx/...", text: $doi)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("URL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("https://...", text: $url)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstract").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: $abstract)
                        .font(.system(size: 12))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .scrollContentBackground(.hidden)
                }
            }
            .padding(20)
        }
    }

    private func addManualPaper() {
        let authors = authorsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let year = Int(yearText.trimmingCharacters(in: .whitespaces))

        let paper = Paper(
            id: UUID().uuidString,
            doi: { let d = doi.trimmingCharacters(in: .whitespacesAndNewlines); return d.isEmpty ? nil : d }(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: authors,
            publicationDate: year.map { "\($0)" } ?? "",
            publicationYear: year,
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
            citedByCount: 0,
            abstract: abstract.trimmingCharacters(in: .whitespacesAndNewlines),
            landingPageUrl: url.trimmingCharacters(in: .whitespacesAndNewlines),
            track: topicName,
            addedAt: Date()
        )
        onAdd([paper])
        dismiss()
    }
}
