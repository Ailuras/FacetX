import SwiftUI
import WebKit

struct AddPaperView: View {
    let topicName: String
    let onAdd: ([Paper]) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case search, manualOrPdf
        var title: String {
            switch self {
            case .search: return L10n.pick("Scholar", "学术")
            case .manualOrPdf: return L10n.pick("Manual/PDF", "手动/PDF")
            }
        }
    }
    @State private var tab = Tab.search

    // Google Scholar Search
    @State private var queryText = ""
    @State private var activeQuery = ""
    @State private var importedPaperTitles: Set<String> = []
    @State private var isEnriching = false
    @State private var enrichingTitle = ""

    // Manual & PDF Shared States
    @State private var title = ""
    @State private var authorsText = ""
    @State private var yearText = ""
    @State private var venue = ""
    @State private var doi = ""
    @State private var url = ""
    @State private var abstract = ""
    
    // PDF status
    @State private var isExtracting = false
    @State private var isPdfDropTargeted = false
    @State private var pendingPdfData: Data?
    @State private var pendingPdfFilename: String? = nil

    private var fetcher: OpenAlexFetcher {
        OpenAlexFetcher(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Unified single-row top info bar
                HStack(spacing: 8) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                    
                    if tab == .search {
                        TextField(L10n.pick("Search...", "检索…"), text: $queryText)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit {
                                activeQuery = queryText
                            }
                        
                        Button {
                            activeQuery = queryText
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 22)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(queryText.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Spacer()
                        Text(L10n.pick("Drag PDF or fill fields below", "拖入 PDF 或在下方填写"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(FacetTheme.quietPanel)
                
                Divider()

                // Content View
                Group {
                    switch tab {
                    case .search:
                        GoogleScholarWebView(query: activeQuery, importedTitles: importedPaperTitles) { metadata in
                            handleImportFromScholar(metadata)
                        }
                    case .manualOrPdf:
                        manualOrPdfTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Background metadata lookup indicator
            if isEnriching {
                ZStack {
                    Color.black.opacity(0.15)
                    
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L10n.pick("Enriching metadata...", "正在补全元数据…"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(enrichingTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(color: Color.black.opacity(0.1), radius: 6)
                    )
                    .frame(width: 240)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            loadImportedTitles()
        }
    }

    private func loadImportedTitles() {
        let existing = PaperStore.shared.papers.map { $0.title }
        importedPaperTitles = Set(existing)
    }

    // MARK: - Google Scholar Import Helper

    private func handleImportFromScholar(_ metadata: [String: Any]) {
        let titleVal = metadata["title"] as? String ?? ""
        let authorsVal = metadata["authors"] as? [String] ?? []
        let venueVal = metadata["venue"] as? String ?? ""
        let yearVal = metadata["year"] as? Int
        let snippetVal = metadata["snippet"] as? String ?? ""
        let urlVal = metadata["url"] as? String ?? ""
        let pdfUrlVal = metadata["pdfUrl"] as? String

        let fallbackPaper = Paper(
            id: "gs-\(UUID().uuidString)",
            title: titleVal,
            authors: authorsVal,
            publicationYear: yearVal,
            venue: venueVal,
            abstract: snippetVal,
            landingPageUrl: urlVal,
            pdfUrl: pdfUrlVal,
            track: topicName,
            addedAt: Date()
        )

        isEnriching = true
        enrichingTitle = titleVal

        Task {
            var finalPaper = fallbackPaper
            
            // Asynchronously match OpenAlex by Title
            let results = await fetcher.fetchByTitle(titleVal, limit: 3)
            if let match = results.first(where: { isSimilarTitle($0.title, titleVal) }) {
                match.track = topicName
                match.addedAt = Date()
                
                // Retain Scholar PDF link if OpenAlex doesn't have it
                if (match.pdfUrl == nil || match.pdfUrl!.isEmpty), let pdf = pdfUrlVal, !pdf.isEmpty {
                    match.pdfUrl = pdf
                }
                // Retain Scholar Landing Page URL if OpenAlex URL is empty
                if match.landingPageUrl.isEmpty && !urlVal.isEmpty {
                    match.landingPageUrl = urlVal
                }
                finalPaper = match
            }
            
            await MainActor.run {
                onAdd([finalPaper])
                importedPaperTitles.insert(titleVal)
                isEnriching = false
                enrichingTitle = ""
            }
        }
    }

    private func isSimilarTitle(_ a: String, _ b: String) -> Bool {
        let cleanA = a.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let cleanB = b.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        guard !cleanA.isEmpty, !cleanB.isEmpty else { return false }
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA)
    }

    // MARK: - Manual & PDF Merged Tab

    private var manualOrPdfTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Compact PDF drop zone
                pdfDropZone
                
                if isExtracting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n.pick("Extracting metadata...", "正在解析文献元数据…"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if let filename = pendingPdfFilename {
                    HStack {
                        Label(filename, systemImage: "paperclip")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            pendingPdfData = nil
                            pendingPdfFilename = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                Divider()
                
                // Form fields
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.pick("Title *", "标题 *")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        TextField(L10n.pick("Paper title", "文献标题"), text: $title)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.pick("Authors", "作者")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        TextField(L10n.pick("Author1, Author2", "作者1, 作者2"), text: $authorsText)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.pick("Year", "年份")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            TextField("2024", text: $yearText)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 70)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.pick("Venue", "来源")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            TextField(L10n.pick("Conference or journal", "会议或期刊"), text: $venue)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("DOI").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("10.xxxx/...", text: $doi)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("URL").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("https://...", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.pick("Abstract", "摘要")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        TextEditor(text: $abstract)
                            .font(.system(size: 11))
                            .frame(height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                            .scrollContentBackground(.hidden)
                    }
                }
                
                Button {
                    addManualOrPdfPaper()
                } label: {
                    Text(pendingPdfData != nil ? L10n.pick("Import & Attach PDF", "导入并附加 PDF") : L10n.pick("Add Paper", "添加文献"))
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.top, 6)
            }
            .padding(12)
        }
        .thinScrollIndicators()
    }

    private var pdfDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(L10n.pick("Drop PDF to auto-extract", "拖入 PDF 自动解析元数据"))
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
            Button(L10n.pick("Choose PDF", "选择 PDF")) {
                choosePdf()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(isPdfDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPdfDropTargeted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            handlePdfFile(at: url)
            return true
        } isTargeted: {
            isPdfDropTargeted = $0
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

        guard let data else { return }
        handlePdfData(data, filename: url.lastPathComponent)
    }

    private func handlePdfData(_ data: Data, filename: String) {
        guard PdfStorage.looksLikePdf(data) else { return }

        pendingPdfData = data
        pendingPdfFilename = filename
        isExtracting = true

        Task {
            let extracted = PdfMetadataExtractor.extract(from: data)
            var matchedPaper: Paper? = nil

            if let doiVal = extracted.doi, !doiVal.isEmpty {
                if let paper = await fetcher.fetchByDOI(doiVal) {
                    matchedPaper = paper
                }
            }

            if matchedPaper == nil, let titleVal = extracted.title, !titleVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let results = await fetcher.fetchByTitle(titleVal, limit: 3)
                if let match = results.first(where: { isSimilarTitle($0.title, titleVal) }) {
                    matchedPaper = match
                }
            }

            await MainActor.run {
                if let paper = matchedPaper {
                    self.title = paper.title
                    self.authorsText = paper.authors.joined(separator: ", ")
                    self.yearText = paper.publicationYear != nil ? String(paper.publicationYear!) : ""
                    self.venue = paper.venue
                    self.abstract = paper.abstract
                    self.doi = paper.doi ?? ""
                    self.url = paper.landingPageUrl
                } else {
                    self.title = extracted.title ?? filename.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
                    self.authorsText = extracted.authors.joined(separator: ", ")
                    self.yearText = extracted.year != nil ? String(extracted.year!) : ""
                    self.venue = ""
                    self.abstract = extracted.abstract ?? ""
                    self.doi = extracted.doi ?? ""
                    self.url = ""
                }
                self.isExtracting = false
            }
        }
    }

    private func addManualOrPdfPaper() {
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
        
        if pendingPdfData != nil {
            guard attachPendingPdf(to: paper) else { return }
            onAdd([paper])
            persistAttachedPdf(for: paper)
        } else {
            onAdd([paper])
        }
        
        importedPaperTitles.insert(paper.title)
        
        // Clear fields
        title = ""
        authorsText = ""
        yearText = ""
        venue = ""
        doi = ""
        url = ""
        abstract = ""
        pendingPdfData = nil
        pendingPdfFilename = nil
    }

    private func attachPendingPdf(to paper: Paper) -> Bool {
        guard let data = pendingPdfData else { return false }
        do {
            let relative = try PdfStorage.current().write(data, forPaperId: paper.id)
            paper.pdfLocalPath = relative
            paper.pdfStatus = PdfStatus.downloaded.rawValue
            return true
        } catch {
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
}
