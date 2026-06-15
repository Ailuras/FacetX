import SwiftUI
import UniformTypeIdentifiers
import PDFKit

/// Sheet for adding a paper to the library.
/// Supports search (DOI/Title), automated PDF drag-and-drop/file parsing, and manual entry.
struct PaperImportView: View {
    let onAdd: (Paper) -> Void

    @Environment(\.dismiss) private var dismiss

    enum Mode { case search, pdf, manual }
    @State private var mode: Mode = .search

    // Search state
    @State private var searchInput = ""
    @State private var searchState: SearchState = .idle
    @State private var searchResults: [Paper] = []
    @State private var selectedPaper: Paper?
    @State private var isSearching = false

    // PDF state
    @State private var pdfFileUrl: URL?
    @State private var isDragging = false
    @State private var showFilePicker = false
    @State private var pendingPdfData: Data?
    @State private var pendingPdfFilename: String?
    @State private var pdfImportState: PDFImportState = .idle

    enum PDFImportState {
        case idle
        case extracting
        case queryingOpenAlex(doi: String)
        case resolvedOpenAlex(Paper)
        case resolvedLocal(title: String, authors: [String], abstract: String, year: Int?)
        case error(String)
    }

    // Manual entry state
    @State private var manualTitle = ""
    @State private var manualAuthors = ""
    @State private var manualYear = ""
    @State private var manualVenue = ""
    @State private var manualDOI = ""
    @State private var manualURL = ""
    @State private var manualAbstract = ""

    enum SearchState { case idle, searching, results, notFound, error(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Picker("", selection: $mode) {
                Text("Search").tag(Mode.search)
                Text("Import PDF").tag(Mode.pdf)
                Text("Manual").tag(Mode.manual)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            switch mode {
            case .search:
                searchPanel
            case .pdf:
                pdfPanel
            case .manual:
                manualPanel
            }
        }
        .frame(width: 520)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handlePDFFile(at: url)
                }
            case .failure(let error):
                pdfImportState = .error("Failed to select file: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add Paper")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Search panel

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DOI OR TITLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.75))
                HStack(spacing: 8) {
                    TextField("e.g. 10.1038/nature12373 or paper title…", text: $searchInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { performSearch() }
                    Button("Search") { performSearch() }
                        .disabled(searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
            }

            searchBody

            Spacer()

            HStack {
                if case .results = searchState {
                    Button("Add to Library") { addSelected() }
                        .disabled(selectedPaper == nil)
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var searchBody: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching OpenAlex…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .results:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(searchResults) { paper in
                    SearchResultRow(paper: paper, isSelected: selectedPaper?.id == paper.id) {
                        selectedPaper = (selectedPaper?.id == paper.id) ? nil : paper
                    }
                }
            }
        case .notFound:
            VStack(alignment: .leading, spacing: 6) {
                Label("No results found on OpenAlex.", systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Switch to Manual Entry") { mode = .manual }
                    .font(.callout)
            }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    // MARK: - PDF Panel

    private var pdfPanel: some View {
        VStack(spacing: 14) {
            switch pdfImportState {
            case .idle:
                pdfUploadBox
                    .dropDestination(for: URL.self) { urls, _ in
                        if let url = urls.first {
                            self.handlePDFFile(at: url)
                            return true
                        }
                        return false
                    } isTargeted: { targeted in
                        self.isDragging = targeted
                    }
                Spacer()
                
            case .extracting:
                loadingStateView(title: "Extracting text from PDF...")
                
            case .queryingOpenAlex(let doi):
                loadingStateView(title: "Resolving metadata online...", subtitle: "DOI found: \(doi)")
                
            case .resolvedOpenAlex(let paper):
                metadataPreviewBox(
                    title: "Metadata Match Found",
                    subtitle: "This paper is indexed in OpenAlex. We will save the PDF as an offline attachment.",
                    infoView: VStack(alignment: .leading, spacing: 8) {
                        previewField("Title", value: paper.title)
                        previewField("Authors", value: paper.authors.joined(separator: ", "))
                        if !paper.venue.isEmpty {
                            previewField("Venue", value: paper.venue)
                        }
                        if let year = paper.publicationYear {
                            previewField("Year", value: String(year))
                        }
                    },
                    primaryAction: { importResolvedOpenAlex(paper) },
                    primaryText: "Import & Attach PDF",
                    secondaryAction: {
                        // Transfer to manual for customization
                        transferToManual(
                            title: paper.title,
                            authors: paper.authors.joined(separator: ", "),
                            year: paper.publicationYear.map { String($0) } ?? "",
                            venue: paper.venue,
                            doi: paper.doi ?? "",
                            url: paper.landingPageUrl,
                            abstract: paper.abstract
                        )
                    },
                    secondaryText: "Customize Manually"
                )
                
            case .resolvedLocal(let title, let authors, let abstract, let year):
                metadataPreviewBox(
                    title: "No Online Match Found",
                    subtitle: "Metadata extracted locally from PDF contents. Review or customize before saving.",
                    infoView: VStack(alignment: .leading, spacing: 8) {
                        previewField("Title", value: title)
                        previewField("Authors", value: authors.isEmpty ? "Unknown" : authors.joined(separator: ", "))
                        if let y = year {
                            previewField("Year", value: String(y))
                        }
                        if !abstract.isEmpty {
                            previewField("Abstract", value: abstract)
                        }
                    },
                    primaryAction: { importResolvedLocal(title: title, authors: authors, abstract: abstract, year: year) },
                    primaryText: "Import Local Paper",
                    secondaryAction: {
                        transferToManual(
                            title: title,
                            authors: authors.joined(separator: ", "),
                            year: year.map { String($0) } ?? "",
                            venue: "",
                            doi: "",
                            url: "",
                            abstract: abstract
                        )
                    },
                    secondaryText: "Edit Details"
                )
                
            case .error(let msg):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.red.opacity(0.8))
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Try Another PDF") {
                        pdfImportState = .idle
                        pendingPdfData = nil
                        pdfFileUrl = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(height: 220)
                Spacer()
            }
        }
        .padding(20)
    }

    private var pdfUploadBox: some View {
        VStack(spacing: 14) {
            Image(systemName: isDragging ? "arrow.down.doc.fill" : "doc.badge.plus")
                .font(.system(size: 38))
                .foregroundStyle(isDragging ? Color.accentColor : Color.secondary.opacity(0.8))
                .scaleEffect(isDragging ? 1.15 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDragging)
            
            Text("Drag & Drop Paper PDF here")
                .font(.system(size: 14, weight: .medium))
            
            Text("or click to select from Finder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: isDragging ? [] : [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragging ? Color.accentColor.opacity(0.05) : Color.black.opacity(0.02))
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            showFilePicker = true
        }
    }

    private func loadingStateView(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private func metadataPreviewBox<V: View>(
        title: String,
        subtitle: String,
        infoView: V,
        primaryAction: @escaping () -> Void,
        primaryText: String,
        secondaryAction: @escaping () -> Void,
        secondaryText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                infoView
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 260)

            HStack {
                Button("Reset / Upload Another") {
                    pdfImportState = .idle
                    pendingPdfData = nil
                    pdfFileUrl = nil
                }
                Spacer()
                Button(secondaryText) { secondaryAction() }
                Button(primaryText) { primaryAction() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func previewField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            Text(value)
                .font(.system(size: 12))
                .lineLimit(label == "Abstract" ? 5 : 2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Manual panel

    private var manualPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if pendingPdfData != nil {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text("Linked PDF: \(pendingPdfFilename ?? "Selected document.pdf")")
                        .lineLimit(1)
                    Spacer()
                    Button("Remove File") {
                        pendingPdfData = nil
                        pendingPdfFilename = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }

            manualField("Title *", placeholder: "Paper title", text: $manualTitle)
            manualField("Authors", placeholder: "Author A, Author B, …", text: $manualAuthors)
            
            HStack(spacing: 12) {
                manualField("Year", placeholder: "2024", text: $manualYear)
                    .frame(maxWidth: 90)
                manualField("Venue", placeholder: "Conference or journal", text: $manualVenue)
            }
            
            HStack(spacing: 12) {
                manualField("DOI", placeholder: "10.xxxx/…", text: $manualDOI)
                manualField("URL", placeholder: "https://…", text: $manualURL)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("ABSTRACT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.75))
                TextEditor(text: $manualAbstract)
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.2), width: 1)
                    .cornerRadius(4)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add to Library") { addManual() }
                    .disabled(manualTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func manualField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func handlePDFFile(at url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        let pdfData = try? Data(contentsOf: url)
        if access {
            url.stopAccessingSecurityScopedResource()
        }

        guard let data = pdfData else {
            self.pdfImportState = .error("Failed to read PDF file data.")
            return
        }

        handlePDFData(data, filename: url.lastPathComponent)
    }

    private func isSimilarTitle(_ a: String, _ b: String) -> Bool {
        let cleanA = a.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let cleanB = b.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        if cleanA.isEmpty || cleanB.isEmpty { return false }
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA)
    }

    private func handlePDFData(_ data: Data, filename: String) {
        pdfImportState = .extracting
        pendingPdfFilename = filename
        pendingPdfData = data

        guard PdfStorage.looksLikePdf(data) else {
            self.pdfImportState = .error("The selected file does not appear to be a valid PDF document.")
            return
        }

        Task {
            let extracted = PdfMetadataExtractor.extract(from: data)
            let fetcher = OpenAlexFetcher(
                config: ConfigManager.shared.effectiveConfig,
                venues: MetadataStore.shared.venues
            )

            // Step 1: Try by DOI if available
            if let doi = extracted.doi {
                await MainActor.run {
                    self.pdfImportState = .queryingOpenAlex(doi: doi)
                }
                if let paper = await fetcher.fetchByDOI(doi) {
                    await MainActor.run {
                        self.pdfImportState = .resolvedOpenAlex(paper)
                    }
                    return
                }
            }

            // Step 2: Try by Title search as a fallback if title is resolved
            if let title = extracted.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    self.pdfImportState = .queryingOpenAlex(doi: "Title Search: \(title)")
                }
                let results = await fetcher.fetchByTitle(title, limit: 3)
                // Look for a close match in title similarity
                if let matchedPaper = results.first(where: { isSimilarTitle($0.title, title) }) {
                    await MainActor.run {
                        self.pdfImportState = .resolvedOpenAlex(matchedPaper)
                    }
                    return
                }
            }

            // Step 3: Local heuristics fallback
            await MainActor.run {
                self.pdfImportState = .resolvedLocal(
                    title: extracted.title ?? filename.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive),
                    authors: extracted.authors,
                    abstract: extracted.abstract ?? "",
                    year: extracted.year
                )
            }
        }
    }

    private func performSearch() {
        let query = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        selectedPaper = nil
        searchResults = []
        isSearching = true
        searchState = .searching

        let isDOI = query.hasPrefix("10.") || query.contains("doi.org")
        let fetcher = OpenAlexFetcher(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )

        Task {
            if isDOI {
                let result = await fetcher.fetchByDOI(query)
                await MainActor.run {
                    if let paper = result {
                        searchResults = [paper]
                        searchState = .results
                    } else {
                        searchState = .notFound
                    }
                    isSearching = false
                }
            } else {
                let results = await fetcher.fetchByTitle(query, limit: 5)
                await MainActor.run {
                    if results.isEmpty {
                        searchState = .notFound
                    } else {
                        searchResults = results
                        searchState = .results
                    }
                    isSearching = false
                }
            }
        }
    }

    private func addSelected() {
        guard let paper = selectedPaper else { return }
        onAdd(paper)
        dismiss()
    }

    private func savePDFAndGetRelativePath(id: String) -> String? {
        guard let data = pendingPdfData else { return nil }
        do {
            let relativePath = try PdfStorage.current().write(data, forPaperId: id)
            return relativePath
        } catch {
            print("Failed to save PDF locally: \(error)")
            return nil
        }
    }

    private func importResolvedOpenAlex(_ paper: Paper) {
        if let relativePath = savePDFAndGetRelativePath(id: paper.id) {
            paper.pdfLocalPath = relativePath
            paper.pdfStatus = PdfStatus.downloaded.rawValue
        }
        onAdd(paper)
        dismiss()
    }

    private func importResolvedLocal(title: String, authors: [String], abstract: String, year: Int?) {
        let paperId = UUID().uuidString
        var pdfPath: String?
        var pdfStatus: String?

        if let relativePath = savePDFAndGetRelativePath(id: paperId) {
            pdfPath = relativePath
            pdfStatus = PdfStatus.downloaded.rawValue
        }

        let paper = Paper(
            id: paperId,
            doi: nil,
            title: title,
            authors: authors,
            publicationDate: year.map { String($0) } ?? "",
            publicationYear: year,
            venue: "",
            abstract: abstract,
            pdfLocalPath: pdfPath,
            pdfStatus: pdfStatus,
            addedAt: Date()
        )
        onAdd(paper)
        dismiss()
    }

    private func transferToManual(
        title: String,
        authors: String,
        year: String,
        venue: String,
        doi: String,
        url: String,
        abstract: String
    ) {
        manualTitle = title
        manualAuthors = authors
        manualYear = year
        manualVenue = venue
        manualDOI = doi
        manualURL = url
        manualAbstract = abstract
        mode = .manual
    }

    private func addManual() {
        let title = manualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let authors = manualAuthors
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let doi = manualDOI.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(manualYear.trimmingCharacters(in: .whitespacesAndNewlines))
        let venue = manualVenue.trimmingCharacters(in: .whitespacesAndNewlines)
        let abstract = manualAbstract.trimmingCharacters(in: .whitespacesAndNewlines)

        let paperId = UUID().uuidString
        var pdfPath: String?
        var pdfStatus: String?

        if let relativePath = savePDFAndGetRelativePath(id: paperId) {
            pdfPath = relativePath
            pdfStatus = PdfStatus.downloaded.rawValue
        }

        let paper = Paper(
            id: paperId,
            doi: doi.isEmpty ? nil : doi,
            title: title,
            authors: authors,
            publicationDate: year.map { "\($0)" } ?? "",
            publicationYear: year,
            venue: venue,
            abstract: abstract,
            landingPageUrl: url.isEmpty ? "" : url,
            pdfLocalPath: pdfPath,
            pdfStatus: pdfStatus,
            addedAt: Date()
        )
        onAdd(paper)
        dismiss()
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let paper: Paper
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(paper.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !paper.authors.isEmpty {
                        Text(paper.authors.prefix(3).joined(separator: ", "))
                            .lineLimit(1)
                    }
                    if !paper.venue.isEmpty {
                        Text("·")
                        Text(paper.venue)
                            .lineLimit(1)
                    }
                    if !paper.publicationDate.isEmpty {
                        Text("·")
                        Text(paper.publicationDate.prefix(4))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.14)
                          : (hovering ? Color.secondary.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
