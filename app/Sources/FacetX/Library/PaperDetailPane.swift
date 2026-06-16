import FacetXCore
import SwiftUI

struct PaperDetailPane: View {
    let inputPaper: Paper
    /// `Paper` is a class, so in-place edits (status/tags/note) don't change the
    /// `papers` array and won't re-render this pane on their own. The parent
    /// passes the store's `paperVersion` here so each edit gives the view a new
    /// value to diff on, forcing a re-render that reads the updated fields.
    let version: Int
    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var toast: ToastController
    @State private var noteText: String = ""
    @State private var isTranslating = false
    @State private var showTranslation = false

    /// Always read the live copy from the store so status / tag / translation
    /// edits reflect immediately instead of using the captured snapshot.
    private var paper: Paper {
        store.papers.first(where: { $0.id == inputPaper.id }) ?? inputPaper
    }

    var body: some View {
        FacetSidebarContent {
            headerCard
            if paper.isRecommended, !paper.recommendationReason.isEmpty {
                recommendationCard
            }
            statusSection
            tagsSection
            abstractSection
            detailsSection
            notesSection
            pdfSection
            citeSection
        }
        .onAppear { noteText = paper.note }
        .onChange(of: paper.note) { _, new in
            if noteText != new { noteText = new }
        }
        .onChange(of: paper.id) { _, _ in
            noteText = paper.note
            showTranslation = false
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(paper.title)
                .font(.system(size: 15, weight: .bold))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                if !paper.venue.isEmpty {
                    FacetInfoBadge(
                        text: paper.venueAbbr.isEmpty ? paper.venue : paper.venueAbbr,
                        systemImage: "building.2",
                        tint: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)),
                        fill: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)).opacity(0.12)
                    )
                }
                if paper.tier > 0 {
                    FacetInfoBadge(
                        text: L10n.pick("Tier \(paper.tier) · \(String(format: "%.1f", paper.score))",
                                        "T\(paper.tier) · \(String(format: "%.1f", paper.score))"),
                        systemImage: "star",
                        tint: metadata.tierColor(paper.tier),
                        fill: metadata.tierColor(paper.tier).opacity(0.12)
                    )
                }
                if paper.citedByCount > 0 {
                    FacetInfoBadge(
                        text: L10n.pick("\(paper.citedByCount) cites", "被引 \(paper.citedByCount)"),
                        systemImage: "quote.bubble",
                        tint: .secondary,
                        fill: Color.secondary.opacity(0.08)
                    )
                }
                if let year = paper.publicationYear {
                    FacetInfoBadge(
                        text: "\(year)",
                        systemImage: "calendar",
                        tint: .secondary,
                        fill: Color.secondary.opacity(0.08)
                    )
                }
            }

            if !paper.landingPageUrl.isEmpty {
                Button {
                    if let url = URL(string: paper.landingPageUrl) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(L10n.pick("Open Source Page", "打开原文"), systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recommendationCard: some View {
        FacetDetailBox {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(paper.recommendationReason)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button {
                    store.setPaperRecommended(id: paper.id, isRecommended: false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Dismiss recommendation", "取消推荐"))
            }
            .padding(10)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        FacetDetailSection(title: L10n.pick("Status", "状态"), systemImage: "flag") {
            HStack(spacing: 6) {
                ForEach(PaperStatus.allCases, id: \.self) { status in
                    Button {
                        store.setPaperStatus(id: paper.id, status: status)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: status.iconName)
                                .font(.system(size: 13, weight: .medium))
                            Text(statusName(status))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(paper.status == status ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(paper.status == status ? status.iconColor : Color.secondary.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
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

    // MARK: - Tags

    private var tagsSection: some View {
        FacetDetailSection(title: L10n.pick("Tags", "标签"), systemImage: "tag") {
            TagChipEditor(tagsText: tagsBinding, knownColors: appSettings)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Bridges the store's tag array to `TagChipEditor`'s comma-joined string,
    /// diffing on write so the shared chip editor drives add/remove calls.
    private var tagsBinding: Binding<String> {
        Binding(
            get: { paper.tags.joined(separator: ", ") },
            set: { newValue in
                let updated = FacetMetadata.tags(from: newValue)
                let current = paper.tags
                for tag in updated where !current.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    store.addPaperTag(id: paper.id, tag: tag)
                }
                for tag in current where !updated.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    store.removePaperTag(id: paper.id, tag: tag)
                }
            }
        )
    }

    // MARK: - Abstract

    private var abstractSection: some View {
        FacetDetailSection(title: L10n.pick("Abstract", "摘要"), systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                let displayText = showTranslation && !paper.abstractZh.isEmpty ? paper.abstractZh : paper.abstract

                if displayText.isEmpty {
                    Text(L10n.pick("No abstract available.", "暂无摘要。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(displayText)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    if !paper.abstractZh.isEmpty {
                        Button {
                            showTranslation.toggle()
                        } label: {
                            Label(showTranslation ? L10n.pick("Original", "原文") : L10n.pick("Translation", "译文"),
                                  systemImage: "character.book.closed")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    } else if !paper.abstract.isEmpty {
                        Button {
                            translateAbstract()
                        } label: {
                            if isTranslating {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(L10n.pick("Translate", "翻译"), systemImage: "globe")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(isTranslating)
                    }
                }
            }
            .padding(10)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        FacetDetailSection(title: L10n.pick("Details", "详情"), systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 7) {
                if !paper.venue.isEmpty {
                    metaRow(L10n.pick("Venue", "来源"), paper.venue)
                }
                if let doi = paper.doi, !doi.isEmpty {
                    metaRow("DOI", CitationExporter.stripDoiPrefix(doi))
                }
                if !paper.publicationDate.isEmpty {
                    metaRow(L10n.pick("Published", "发表"), paper.publicationDate)
                }
                if let added = paper.addedAt {
                    metaRow(L10n.pick("Added", "添加"), added.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(10)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        FacetDetailSection(title: L10n.pick("Notes", "笔记"), systemImage: "note.text") {
            TextEditor(text: $noteText)
                .font(.system(size: 12))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .onChange(of: noteText) { _, new in
                    store.setPaperNote(id: paper.id, note: new)
                }
        }
    }

    // MARK: - PDF

    private var pdfSection: some View {
        FacetDetailSection(title: "PDF", systemImage: "doc") {
            HStack(spacing: 8) {
                if PdfCoordinator.hasLocalPdf(paper) {
                    pdfButton(L10n.pick("Show in Finder", "在访达中显示"), "folder") {
                        _ = PdfCoordinator.reveal(paper: paper)
                    }
                }
                pdfButton(paper.pdfLocalPath == nil ? L10n.pick("Attach PDF", "附加 PDF") : L10n.pick("Replace", "替换"), "plus") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [.pdf]
                    if panel.runModal() == .OK, let url = panel.url {
                        switch PdfCoordinator.setManualPdf(paper: paper, store: store, from: url) {
                        case .success:
                            toast.show(L10n.pick("PDF attached", "已附加 PDF"), type: .success, duration: 2)
                        case .notPDF:
                            toast.show(L10n.pick("That file is not a PDF", "该文件不是 PDF"), type: .warning)
                        case .failed:
                            toast.show(L10n.pick("Failed to attach PDF", "附加 PDF 失败"), type: .error)
                        }
                    }
                }
                if paper.pdfLocalPath != nil {
                    pdfButton(L10n.pick("Remove", "移除"), "trash", role: .destructive) {
                        PdfCoordinator.removePdf(paper: paper, store: store)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private func pdfButton(_ label: String, _ icon: String, role: ButtonRole? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Cite

    private var citeSection: some View {
        FacetDetailSection(title: L10n.pick("Cite", "引用"), systemImage: "quote.opening") {
            HStack(spacing: 8) {
                citeButton("BibTeX") { CitationExporter.bibtex(for: paper) }
                citeButton("APA") { CitationExporter.apa(for: paper) }
                citeButton("RIS") { CitationExporter.ris(for: paper) }
                citeButton("MD") { CitationExporter.markdown(for: paper) }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private func citeButton(_ label: String, _ value: @escaping () -> String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value(), forType: .string)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func translateAbstract() {
        isTranslating = true
        let settings = LibrarySettings.shared
        let config = ConfigManager.shared.effectiveConfig
        Task {
            do {
                let translator = TranslationService(config: config, apiKey: settings.apiKey)
                let zh = try await translator.translateAbstract(
                    id: paper.id,
                    abstract: paper.abstract,
                    cachedAbstractZh: paper.abstractZh
                )
                store.setPaperTranslation(id: paper.id, abstractZh: zh)
                showTranslation = true
            } catch {
                toast.show(L10n.pick("Translation failed: \(error.localizedDescription)",
                                     "翻译失败：\(error.localizedDescription)"), type: .error)
            }
            isTranslating = false
        }
    }
}
