import SwiftUI

struct PaperDetailPane: View {
    let paper: Paper
    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var noteText: String = ""
    @State private var isTranslating = false
    @State private var showTranslation = false

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
            VStack(alignment: .leading, spacing: 8) {
                if !paper.tags.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(paper.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .medium))
                                Button {
                                    store.removePaperTag(id: paper.id, tag: tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(LabelColor.forTag(tag).opacity(0.12))
                            )
                        }
                    }
                }
                AddTagField { tag in store.addPaperTag(id: paper.id, tag: tag) }
            }
            .padding(10)
        }
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
                        _ = PdfCoordinator.setManualPdf(paper: paper, store: store, from: url)
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
                print("Translation failed: \(error)")
            }
            isTranslating = false
        }
    }
}

// MARK: - Add Tag Field

private struct AddTagField: View {
    let onSubmit: (String) -> Void
    @State private var text = ""
    @State private var showField = false

    var body: some View {
        if showField {
            HStack(spacing: 4) {
                TextField(L10n.pick("New tag", "新标签"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit { commit() }
                Button { commit() } label: {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                Button { showField = false; text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        } else {
            Button { showField = true } label: {
                Label(L10n.pick("Add Tag", "添加标签"), systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onSubmit(trimmed) }
        text = ""
        showField = false
    }
}
