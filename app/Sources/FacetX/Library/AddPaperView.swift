import SwiftUI

struct AddPaperView: View {
    let topicName: String
    let initialPaper: Paper?
    let onSave: (Paper, Data?, String?) -> Void
    let onCancel: () -> Void

    // Form fields
    @State private var title = ""
    @State private var authorsText = ""
    @State private var yearText = ""
    @State private var venue = ""
    @State private var doi = ""
    @State private var url = ""
    @State private var abstract = ""

    // PDF attachment states
    @State private var pendingPdfData: Data?
    @State private var pendingPdfFilename: String? = nil

    // Extraction & Enrichment status
    @State private var isExtracting = false
    @State private var showParsePrompt = false
    @State private var droppedPdfData: Data?
    @State private var droppedPdfFilename = ""
    @State private var isPdfDropTargeted = false

    private var fetcher: OpenAlexFetcher {
        OpenAlexFetcher(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Only show PDF Drop Zone for manual add (if initialPaper doesn't come from Scholar)
                    if initialPaper?.id.hasPrefix("gs-") != true {
                        pdfDropZone
                        
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
                    }
                    
                    // Metadata Review/Edit Form
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
                                .frame(height: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                )
                                .scrollContentBackground(.hidden)
                        }
                    }
                    
                    // Unified Save Button
                    Button {
                        savePaper()
                    } label: {
                        Text(L10n.pick("Save Paper", "保存文献"))
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExtracting)
                    .padding(.top, 6)
                }
                .padding(12)
            }
            .thinScrollIndicators()
            
            // Background metadata lookup or extraction indicator
            if isExtracting {
                ZStack {
                    Color.black.opacity(0.15)
                    
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L10n.pick("Parsing metadata...", "正在解析文献元数据…"))
                            .font(.system(size: 12, weight: .semibold))
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                        }
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
            populateForm()
        }
        // Confirmation alert for PDF drops
        .alert(L10n.pick("Parse PDF Metadata?", "是否解析 PDF 元数据？"), isPresented: $showParsePrompt) {
            Button(L10n.pick("Parse & Replace", "解析并替换")) {
                if let data = droppedPdfData {
                    runPdfExtraction(data: data, filename: droppedPdfFilename)
                }
            }
            Button(L10n.pick("Skip (Attach Only)", "仅附加 PDF"), role: .cancel) {
                pendingPdfData = droppedPdfData
                pendingPdfFilename = droppedPdfFilename
            }
        } message: {
            Text(L10n.pick("FacetX can extract the title and authors from the PDF, then query OpenAlex to auto-populate the metadata form.",
                           "FacetX 可以从 PDF 提取标题与作者，并查询 OpenAlex 来自动填充元数据表单。"))
        }
    }

    private func populateForm() {
        guard let paper = initialPaper else { return }
        self.title = paper.title
        self.authorsText = paper.authors.joined(separator: ", ")
        self.yearText = paper.publicationYear != nil ? String(paper.publicationYear!) : ""
        self.venue = paper.venue
        self.abstract = paper.abstract
        self.doi = paper.doi ?? ""
        self.url = paper.landingPageUrl
        self.pendingPdfData = nil
        self.pendingPdfFilename = nil
        
        // If paper was imported from Google Scholar, run background OpenAlex metadata lookup
        if paper.id.hasPrefix("gs-") {
            runScholarEnrichment(for: paper)
        }
    }

    private func runScholarEnrichment(for paper: Paper) {
        isExtracting = true
        
        Task {
            let titleVal = paper.title
            let results = await fetcher.fetchByTitle(titleVal, limit: 3)
            
            await MainActor.run {
                if let match = results.first(where: { isSimilarTitle($0.title, titleVal) }) {
                    self.title = match.title
                    self.authorsText = match.authors.joined(separator: ", ")
                    self.yearText = match.publicationYear != nil ? String(match.publicationYear!) : ""
                    self.venue = match.venue
                    self.abstract = match.abstract
                    self.doi = match.doi ?? ""
                    self.url = match.landingPageUrl
                }
                self.isExtracting = false
            }
        }
    }

    private var pdfDropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(L10n.pick("Drop PDF to import", "拖入 PDF 导入文献"))
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
            Button(L10n.pick("Choose PDF", "选择 PDF")) {
                choosePdf()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
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
        
        droppedPdfData = data
        droppedPdfFilename = url.lastPathComponent
        showParsePrompt = true
    }

    private func runPdfExtraction(data: Data, filename: String) {
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

    private func savePaper() {
        let cleanAuthors = authorsText
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
            id: initialPaper?.id ?? UUID().uuidString,
            doi: { let d = doi.trimmingCharacters(in: .whitespacesAndNewlines); return d.isEmpty ? nil : d }(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: cleanAuthors,
            publicationDate: pubDate,
            publicationYear: pubYear,
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
            citedByCount: initialPaper?.citedByCount ?? 0,
            abstract: abstract.trimmingCharacters(in: .whitespacesAndNewlines),
            landingPageUrl: url.trimmingCharacters(in: .whitespacesAndNewlines),
            pdfUrl: initialPaper?.pdfUrl,
            track: topicName,
            addedAt: initialPaper?.addedAt ?? Date()
        )
        
        onSave(paper, pendingPdfData, pendingPdfFilename)
    }

    private func isSimilarTitle(_ a: String, _ b: String) -> Bool {
        let cleanA = a.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let cleanB = b.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        guard !cleanA.isEmpty, !cleanB.isEmpty else { return false }
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA)
    }
}
