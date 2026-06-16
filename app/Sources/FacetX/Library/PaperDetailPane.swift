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
            VStack(alignment: .leading, spacing: 0) {
                titleCard
                statusPicker
                tagsSection
                metaSection
                abstractSection
                notesSection
                pdfSection
                citeSection
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            noteText = paper.note
        }
        .onChange(of: paper.note) { _, new in
            if noteText != new { noteText = new }
        }
    }

    // MARK: - Title

    private var titleCard: some View {
        FacetDetailSection(title: paper.title, systemImage: "doc.text") {
            FacetDetailBox {
                VStack(alignment: .leading, spacing: 6) {
                    if !paper.authors.isEmpty {
                        Text(paper.authors.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
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
                                text: "Tier \(paper.tier) · Score \(String(format: "%.1f", paper.score))",
                                systemImage: "star",
                                tint: metadata.tierColor(paper.tier),
                                fill: metadata.tierColor(paper.tier).opacity(0.12)
                            )
                        }
                        if paper.citedByCount > 0 {
                            FacetInfoBadge(
                                text: "\(paper.citedByCount) cites",
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
                }
            }
        }
    }

    // MARK: - Status

    private var statusPicker: some View {
        FacetDetailSection(title: "Status", systemImage: "flag") {
            FacetDetailBox {
                HStack(spacing: 8) {
                    ForEach(PaperStatus.allCases, id: \.self) { status in
                        Button {
                            store.setPaperStatus(id: paper.id, status: status)
                        } label: {
                            Label(status.displayName, systemImage: status.iconName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(paper.status == status ? .white : .primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(paper.status == status ? status.iconColor : Color.secondary.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        FacetDetailSection(title: "Tags", systemImage: "tag") {
            FacetDetailBox {
                VStack(alignment: .leading, spacing: 8) {
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

                    AddTagField { tag in
                        store.addPaperTag(id: paper.id, tag: tag)
                    }
                }
            }
        }
    }

    // MARK: - Meta

    private var metaSection: some View {
        FacetDetailSection(title: "Details", systemImage: "info.circle") {
            FacetDetailBox {
                VStack(alignment: .leading, spacing: 6) {
                    if !paper.venue.isEmpty {
                        metaRow("Venue", paper.venue)
                    }
                    if let doi = paper.doi, !doi.isEmpty {
                        metaRow("DOI", CitationExporter.stripDoiPrefix(doi))
                    }
                    if !paper.landingPageUrl.isEmpty {
                        Button {
                            if let url = URL(string: paper.landingPageUrl) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Open Link")
                                .font(.system(size: 11))
                        }
                    }
                    if let added = paper.addedAt {
                        metaRow("Added", added.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        }
    }

    // MARK: - Abstract

    private var abstractSection: some View {
        FacetDetailSection(title: "Abstract", systemImage: "text.alignleft") {
            FacetDetailBox {
                VStack(alignment: .leading, spacing: 8) {
                    let displayText = showTranslation && !paper.abstractZh.isEmpty
                        ? paper.abstractZh
                        : paper.abstract

                    if displayText.isEmpty {
                        Text("No abstract available.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayText)
                            .font(.system(size: 12))
                            .lineSpacing(3)
                    }

                    if !paper.abstractZh.isEmpty {
                        Button {
                            showTranslation.toggle()
                        } label: {
                            Text(showTranslation ? "Show Original" : "Show Translation")
                                .font(.system(size: 11))
                        }
                    }

                    if !paper.abstract.isEmpty, paper.abstractZh.isEmpty {
                        Button {
                            translateAbstract()
                        } label: {
                            if isTranslating {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Translate")
                                    .font(.system(size: 11))
                            }
                        }
                        .disabled(isTranslating)
                    }
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        FacetDetailSection(title: "Notes", systemImage: "note.text") {
            FacetDetailBox {
                TextEditor(text: $noteText)
                    .font(.system(size: 12))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .onChange(of: noteText) { _, new in
                        store.setPaperNote(id: paper.id, note: new)
                    }
            }
        }
    }

    // MARK: - PDF

    private var pdfSection: some View {
        FacetDetailSection(title: "PDF", systemImage: "doc") {
            FacetDetailBox {
                HStack(spacing: 8) {
                    if PdfCoordinator.hasLocalPdf(paper) {
                        Button {
                            _ = PdfCoordinator.reveal(paper: paper)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                                .font(.system(size: 11))
                        }
                    }

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [.pdf]
                        if panel.runModal() == .OK, let url = panel.url {
                            let result = PdfCoordinator.setManualPdf(paper: paper, store: store, from: url)
                            print("PDF set result: \(result)")
                        }
                    } label: {
                        Label("Set PDF...", systemImage: "plus")
                            .font(.system(size: 11))
                    }

                    if paper.pdfLocalPath != nil {
                        Button(role: .destructive) {
                            PdfCoordinator.removePdf(paper: paper, store: store)
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cite

    private var citeSection: some View {
        FacetDetailSection(title: "Cite", systemImage: "quote.opening") {
            FacetDetailBox {
                VStack(alignment: .leading, spacing: 4) {
                    citeButton("Copy BibTeX") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CitationExporter.bibtex(for: paper), forType: .string)
                    }
                    citeButton("Copy APA") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CitationExporter.apa(for: paper), forType: .string)
                    }
                    citeButton("Copy RIS") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CitationExporter.ris(for: paper), forType: .string)
                    }
                    citeButton("Copy Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CitationExporter.markdown(for: paper), forType: .string)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .lineLimit(3)
            Spacer()
        }
    }

    private func citeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
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
                TextField("New tag", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit {
                        commit()
                    }
                Button {
                    commit()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                Button {
                    showField = false
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                showField = true
            } label: {
                Label("Add Tag", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSubmit(trimmed)
        }
        text = ""
        showField = false
    }
}
