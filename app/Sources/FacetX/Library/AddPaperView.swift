import SwiftUI

struct AddPaperView: View {
    let topicName: String
    let onAdd: ([Paper]) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case search, pdf, manual
        var title: String {
            switch self {
            case .search: return "OpenAlex"
            case .pdf:    return "PDF"
            case .manual: return L10n.pick("Manual", "手动")
            }
        }
    }
    @State private var tab = Tab.search

    // Search
    @State private var queryText = ""
    @State private var isSearching = false
    @State private var searchResults: [Paper] = []
    @State private var selectedPaperIDs: Set<String> = []

    // PDF
    @State private var pdfImportState: PDFImportState = .idle
    @State private var pendingPdfData: Data?
    @State private var isPdfDropTargeted = false

    // Manual
    @State private var title = ""
    @State private var authorsText = ""
    @State private var yearText = ""
    @State private var venue = ""
    @State private var doi = ""
    @State private var url = ""
    @State private var abstract = ""

    enum PDFImportState {
        case idle
        case extracting
        case querying(String)
        case resolvedOpenAlex(Paper)
        case resolvedLocal(title: String, authors: [String], abstract: String, year: Int?)
        case error(String)
    }

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
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Group {
                switch tab {
                case .search: searchTab
                case .pdf: pdfTab
                case .manual: manualTab
                }
            }
            .frame(minHeight: 300)
        }
        .frame(width: 500)
    }

    private var header: some View {
        HStack {
            Text(L10n.pick("Add Paper to \(topicName)", "向 \(topicName) 添加文献")).font(.headline)
            Spacer()
            Button(L10n.t(.cancel)) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if !selectedPaperIDs.isEmpty {
                Button(L10n.pick("Add \(selectedPaperIDs.count) Selected", "添加 \(selectedPaperIDs.count) 篇")) {
                    let papers = searchResults.filter { selectedPaperIDs.contains($0.id) }
                    onAdd(papers)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if tab == .pdf, let action = pdfPrimaryAction {
                Button(pdfPrimaryTitle) { action() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if tab == .manual, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(L10n.pick("Add", "添加")) {
                    addManualPaper()
                }
                .buttonStyle(.borderedProminent)
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
                TextField(L10n.pick("DOI or title...", "DOI 或标题…"), text: $queryText)
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
                    Text(L10n.pick("Search by DOI or title to find papers from OpenAlex.",
                                   "输入 DOI 或标题，从 OpenAlex 检索文献。"))
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
                if !paper.publicationDate.isEmpty {
                    Text(paper.publicationDate)
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

    // MARK: - PDF Tab

    private var pdfTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch pdfImportState {
            case .idle:
                pdfDropZone
            case .extracting:
                progressRow(L10n.pick("Extracting metadata from PDF...", "正在从 PDF 抽取元数据…"))
            case .querying(let label):
                progressRow(L10n.pick("Looking up \(label) on OpenAlex...", "正在 OpenAlex 查询 \(label)…"))
            case .resolvedOpenAlex(let paper):
                pdfPreview(
                    title: L10n.pick("OpenAlex match found", "已匹配 OpenAlex"),
                    subtitle: L10n.pick("The PDF will be attached to this paper.",
                                        "该 PDF 将作为附件保存到这篇文献。"),
                    fields: [
                        (L10n.pick("Title", "标题"), paper.title),
                        (L10n.pick("Authors", "作者"), paper.authors.joined(separator: ", ")),
                        (L10n.pick("Venue", "来源"), paper.venue),
                        (L10n.pick("Date", "日期"), paper.publicationDate)
                    ]
                )
            case .resolvedLocal(let title, let authors, let abstract, let year):
                pdfPreview(
                    title: L10n.pick("Local metadata extracted", "已抽取本地元数据"),
                    subtitle: L10n.pick("No confident OpenAlex match was found. Review before importing.",
                                        "未找到可靠的 OpenAlex 匹配；导入前请检查。"),
                    fields: [
                        (L10n.pick("Title", "标题"), title),
                        (L10n.pick("Authors", "作者"), authors.joined(separator: ", ")),
                        (L10n.pick("Year", "年份"), year.map(String.init) ?? ""),
                        (L10n.pick("Abstract", "摘要"), abstract)
                    ]
                )
            case .error(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button(L10n.pick("Choose Another PDF", "选择其他 PDF")) { choosePdf() }
                }
            }
            Spacer()
        }
        .padding(20)
    }

    private var pdfDropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(L10n.pick("Drop a PDF here", "将 PDF 拖到这里"))
                .font(.system(size: 14, weight: .semibold))
            Text(L10n.pick("FacetX will extract DOI, title, authors and abstract, then try to match OpenAlex.",
                           "FacetX 会抽取 DOI、标题、作者和摘要，并尝试匹配 OpenAlex。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                choosePdf()
            } label: {
                Label(L10n.pick("Choose PDF", "选择 PDF"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .padding(18)
        .background(isPdfDropTargeted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPdfDropTargeted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            handlePdfFile(at: url)
            return true
        } isTargeted: {
            isPdfDropTargeted = $0
        }
    }

    private func progressRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pdfPreview(title: String, subtitle: String, fields: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(fields.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.0) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.0.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(field.1)
                            .font(.system(size: 12))
                            .lineLimit(field.0 == L10n.pick("Abstract", "摘要") ? 5 : 2)
                    }
                }
            }
            Button(L10n.pick("Choose Another PDF", "选择其他 PDF")) { choosePdf() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pdfPrimaryTitle: String {
        switch pdfImportState {
        case .resolvedOpenAlex:
            return L10n.pick("Import & Attach PDF", "导入并附加 PDF")
        case .resolvedLocal:
            return L10n.pick("Import Local Paper", "导入本地文献")
        default:
            return ""
        }
    }

    private var pdfPrimaryAction: (() -> Void)? {
        switch pdfImportState {
        case .resolvedOpenAlex(let paper):
            return { importResolvedOpenAlex(paper) }
        case .resolvedLocal(let title, let authors, let abstract, let year):
            return { importResolvedLocal(title: title, authors: authors, abstract: abstract, year: year) }
        default:
            return nil
        }
    }

    private func choosePdf() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            handlePdfFile(at: url)
        }
    }

    private func handlePdfFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }

        guard let data else {
            pdfImportState = .error(L10n.pick("Could not read this PDF.", "无法读取该 PDF。"))
            return
        }
        handlePdfData(data, filename: url.lastPathComponent)
    }

    private func handlePdfData(_ data: Data, filename: String) {
        guard PdfStorage.looksLikePdf(data) else {
            pdfImportState = .error(L10n.pick("That file does not look like a PDF.", "该文件看起来不是 PDF。"))
            return
        }

        pendingPdfData = data
        pdfImportState = .extracting

        Task {
            let extracted = PdfMetadataExtractor.extract(from: data)

            if let doi = extracted.doi, !doi.isEmpty {
                pdfImportState = .querying("DOI \(doi)")
                if let paper = await fetcher.fetchByDOI(doi) {
                    paper.track = topicName
                    pdfImportState = .resolvedOpenAlex(paper)
                    return
                }
            }

            if let title = extracted.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pdfImportState = .querying(title)
                let results = await fetcher.fetchByTitle(title, limit: 3)
                if let match = results.first(where: { isSimilarTitle($0.title, title) }) {
                    match.track = topicName
                    pdfImportState = .resolvedOpenAlex(match)
                    return
                }
            }

            let fallbackTitle = extracted.title
                ?? filename.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            pdfImportState = .resolvedLocal(
                title: fallbackTitle,
                authors: extracted.authors,
                abstract: extracted.abstract ?? "",
                year: extracted.year
            )
        }
    }

    private func importResolvedOpenAlex(_ paper: Paper) {
        guard attachPendingPdf(to: paper) else { return }
        onAdd([paper])
        persistAttachedPdf(for: paper)
        dismiss()
    }

    private func importResolvedLocal(title: String, authors: [String], abstract: String, year: Int?) {
        let id = UUID().uuidString
        let date = year.map(String.init) ?? ""
        let paper = Paper(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: authors,
            publicationDate: date,
            publicationYear: year,
            venue: "",
            abstract: abstract.trimmingCharacters(in: .whitespacesAndNewlines),
            landingPageUrl: "",
            track: topicName,
            addedAt: Date()
        )
        guard attachPendingPdf(to: paper) else { return }
        onAdd([paper])
        persistAttachedPdf(for: paper)
        dismiss()
    }

    private func attachPendingPdf(to paper: Paper) -> Bool {
        guard let data = pendingPdfData else {
            pdfImportState = .error(L10n.pick("No PDF data is available.", "没有可用的 PDF 数据。"))
            return false
        }
        do {
            let relative = try PdfStorage.current().write(data, forPaperId: paper.id)
            paper.pdfLocalPath = relative
            paper.pdfStatus = PdfStatus.downloaded.rawValue
            return true
        } catch {
            pdfImportState = .error(L10n.pick("Could not save the PDF: \(error.localizedDescription)",
                                             "无法保存 PDF：\(error.localizedDescription)"))
            return false
        }
    }

    private func persistAttachedPdf(for paper: Paper) {
        guard let path = paper.pdfLocalPath, let data = pendingPdfData else { return }
        PaperStore.shared.savePdf(id: paper.id, result: PdfFetchResult(
            status: .downloaded,
            url: paper.pdfUrl,
            source: "manual-import",
            localPath: path,
            byteSize: data.count,
            sha256: PdfStorage.sha256Hex(data)
        ))
    }

    private func isSimilarTitle(_ a: String, _ b: String) -> Bool {
        let cleanA = a.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let cleanB = b.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        guard !cleanA.isEmpty, !cleanB.isEmpty else { return false }
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA)
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
                    Text(L10n.pick("Title *", "标题 *")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField(L10n.pick("Paper title", "文献标题"), text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.pick("Authors", "作者")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField(L10n.pick("Author1, Author2", "作者1, 作者2"), text: $authorsText)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.pick("Date", "日期")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("2024-06-15", text: $yearText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.pick("Venue", "来源")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField(L10n.pick("Conference or journal", "会议或期刊"), text: $venue)
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
                    Text(L10n.pick("Abstract", "摘要")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
        let dateText = yearText.trimmingCharacters(in: .whitespaces)
        let pubYear: Int?
        let pubDate: String
        if dateText.isEmpty {
            pubYear = nil
            pubDate = ""
        } else if dateText.count >= 4, let y = Int(dateText.prefix(4)) {
            pubYear = y
            pubDate = dateText
        } else {
            pubYear = nil
            pubDate = dateText
        }

        let paper = Paper(
            id: UUID().uuidString,
            doi: { let d = doi.trimmingCharacters(in: .whitespacesAndNewlines); return d.isEmpty ? nil : d }(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: authors,
            publicationDate: pubDate,
            publicationYear: pubYear,
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
