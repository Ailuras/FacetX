import SwiftUI
import AppKit

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selectedPaperIds: Set<String>
    var metadata: MetadataStore
    let highlightsDailyRecommendations: Bool
    /// Show the per-row status marker only in mixed-status views (Recommend, All).
    let showsStatusMarker: Bool
    let onCancelRecommendation: (Paper) -> Void
    let onSelectionChange: (Set<String>) -> Void
    let onCopyBibtex: ([Paper]) -> Void
    let onUpdatePaper: ([Paper]) -> Void
    let onDeletePaper: ([Paper]) -> Void
    let onSetStatus: ([Paper], PaperStatus) -> Void
    let onAddToCollection: ([Paper], String) -> Void
    let collections: [PaperCollection]

    var body: some View {
        // Native List selection (multi-select, ⌘A, keyboard nav) stays in charge;
        // only its full-width highlight is suppressed by ListSelectionHighlightDisabler,
        // so the rounded card border is the sole selection cue (system accent).
        ScrollViewReader { proxy in
        List(selection: $selectedPaperIds) {
            ForEach(papers) { paper in
                PaperRowView(
                    paper: paper,
                    metadata: metadata,
                    isDailyRecommendation: highlightsDailyRecommendations,
                    showsStatusMarker: showsStatusMarker,
                    isSelected: selectedPaperIds.contains(paper.id),
                    status: paper.status,
                    hasPdf: PdfStatus(rawValue: paper.pdfStatus ?? "") == .downloaded
                )
                .tag(paper.id)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9))
                .listRowBackground(Color.clear)
                .background(ListSelectionHighlightDisabler())
                .contextMenu {
                    // Finder-style: act on the whole selection if this row is in
                    // it, otherwise just this row.
                    let targets = selectedPaperIds.contains(paper.id)
                        ? papers.filter { selectedPaperIds.contains($0.id) }
                        : [paper]
                    let suffix = targets.count > 1 ? " (\(targets.count))" : ""
                    Button {
                        onCopyBibtex(targets)
                    } label: {
                        Label(L10n.t(.cite) + suffix, systemImage: "doc.on.doc")
                    }
                    Button {
                        onUpdatePaper(targets)
                    } label: {
                        Label(L10n.t(.cmdUpdatePaper) + suffix, systemImage: "arrow.clockwise")
                    }
                    Menu {
                        ForEach(PaperStatus.allCases, id: \.self) { status in
                            Button(status.displayName) { onSetStatus(targets, status) }
                        }
                    } label: {
                        Label(L10n.t(.cmdSetStatus), systemImage: "flag")
                    }
                    if !collections.isEmpty {
                        Menu {
                            ForEach(collections) { collection in
                                Button(collection.name) { onAddToCollection(targets, collection.id) }
                            }
                        } label: {
                            Label(L10n.t(.cmdAddToCollection), systemImage: "folder")
                        }
                    }
                    if highlightsDailyRecommendations {
                        Button(L10n.t(.cancelRecommendation)) {
                            onCancelRecommendation(paper)
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeletePaper(targets)
                    } label: {
                        Label(L10n.t(.cmdDeletePaper) + suffix, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 10)
        .onChange(of: selectedPaperIds) { _, ids in
            onSelectionChange(ids)
            // Keep a programmatically selected paper (⌘↑/⌘↓, status advance)
            // in view. scrollTo without an anchor is a no-op when it's already
            // visible, so ordinary clicks don't jump.
            if ids.count == 1, let only = ids.first {
                proxy.scrollTo(only)
            }
        }
        .overlay {
            if papers.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No papers here",
                    message: "Press ⌘R to fetch papers or adjust your filters"
                )
            }
        }
        }
    }
}

// MARK: - Native selection highlight removal

/// Reaches the `NSTableView` backing the SwiftUI `List` and turns off its
/// built-in selection highlight. Selection state — multi-select, ⌘A, keyboard
/// navigation — is untouched; only the full-width system fill is removed, so
/// the row card's accent border is the sole selection cue. Installed as a tiny
/// hidden view inside a row, whose superview chain leads to the table.
private struct ListSelectionHighlightDisabler: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var applied = false }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // One-shot: once the backing table is found and patched, later updates
        // do no work at all — no walk, no dispatch.
        guard !context.coordinator.applied else { return }
        DispatchQueue.main.async {
            var view: NSView? = nsView
            while let current = view {
                if let table = current as? NSTableView {
                    table.selectionHighlightStyle = .none
                    context.coordinator.applied = true
                    return
                }
                view = current.superview
            }
        }
    }
}

// MARK: - Row

private struct PaperRowView: View {
    let paper: Paper
    var metadata: MetadataStore
    let isDailyRecommendation: Bool
    let showsStatusMarker: Bool
    let isSelected: Bool
    /// Passed as a value (not read off the `Paper` reference) so the row
    /// re-renders the moment the status changes — a class mutation alone would
    /// not change any of the row's inputs and SwiftUI would skip the redraw.
    let status: PaperStatus
    /// Whether a validated PDF is stored locally. Passed as a value (like
    /// `status`) so the row re-renders when a PDF is fetched, set, or removed.
    let hasPdf: Bool

    @State private var isHovering = false

    private let cornerRadius: CGFloat = 8
    /// Distinct from the (blue) selection accent so a selected today-pick still
    /// reads clearly as selected.
    private let todayColor = Color.orange
    /// System accent for the selection border, resolved directly from AppKit.
    private let accent = Color(nsColor: .controlAccentColor)

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    private var isTodayRecommended: Bool {
        guard isDailyRecommendation, let recommendedAt = paper.recommendedAt else { return false }
        return Calendar.current.isDateInToday(recommendedAt)
    }

    /// Visible (non-archived) topic labels, capped so they never crowd out the
    /// trailing date on a narrow row.
    private var topics: [String] {
        Array(metadata.visibleTopicNames(in: paper.track).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if !paper.venueAbbr.isEmpty {
                    TagChip.venue(paper.venueAbbr, color: venueColor)
                }
                TagChip.score(paper.score, color: metadata.tierColor(paper.tier))

                ForEach(topics, id: \.self) { topic in
                    TagChip(text: topic, color: metadata.topicColor(topic))
                }

                Spacer(minLength: 8)

                if isTodayRecommended {
                    TagChip(text: "Today", icon: "sparkles", color: todayColor)
                }
                if hasPdf {
                    TagChip.pdf().help(L10n.t(.openPDF))
                }
                if !paper.publicationDate.isEmpty {
                    TagChip.date(paper.publicationDate)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if showsStatusMarker {
                StatusCornerMarker(color: status.iconColor, cornerRadius: cornerRadius)
                    .frame(width: 18, height: 18)
                    .help(status.displayName)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    // Selection is conveyed by the border only (no fill), per the card design.
    private var fillColor: Color {
        if isTodayRecommended { return todayColor.opacity(0.07) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color(nsColor: .controlBackgroundColor).opacity(0.62)
    }

    private var borderColor: Color {
        if isSelected { return accent.opacity(0.9) }
        if isTodayRecommended { return todayColor.opacity(0.5) }
        if isHovering { return accent.opacity(0.30) }
        return Color.primary.opacity(0.08)
    }
}

private struct StatusCornerMarker: View {
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        TopTrailingCorner(cornerRadius: cornerRadius)
            .fill(color.opacity(0.72))
    }
}

private struct TopTrailingCorner: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
