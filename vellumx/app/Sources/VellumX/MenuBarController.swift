import SwiftUI
import AppKit
import Observation

/// Owns the menu bar status item.
///
/// We deliberately do NOT use SwiftUI's `MenuBarExtra` with a custom `Image`
/// label: that path repeatedly re-resolves the icon and pins a CPU core at
/// ~99% (observed and fixed the same way in the sibling FacetX app). Instead we
/// drive an AppKit `NSStatusItem` directly and pop the SwiftUI content in an
/// `NSPopover`, which is stable.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    private let store: PaperStore
    private let settings: AppSettings

    init(store: PaperStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                store: store,
                closePopover: { [weak self] in self?.popover.performClose(nil) }
            )
        )

        // Show/hide the status item in step with the setting (default on).
        observeMenuBarEnabled()
    }

    private func observeMenuBarEnabled() {
        withObservationTracking {
            apply(enabled: settings.menuBarEnabled)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeMenuBarEnabled()
            }
        }
    }

    private func apply(enabled: Bool) {
        if enabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = Self.icon
                button.image?.isTemplate = true   // adapts to light/dark menu bar
                button.action = #selector(togglePopover)
                button.target = self
            }
            statusItem = item
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
            popover.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
                popoverWindow.level = .popUpMenu
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Custom menu bar icon from the bundled template PNG, falling back to an
    /// SF Symbol if the resource is missing.
    static let icon: NSImage = {
        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        let sym = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "VellumX")
        sym?.isTemplate = true
        return sym ?? NSImage()
    }()
}

/// The popover content: today's recommendations + quick actions. Plain SwiftUI,
/// hosted in an NSPopover (not MenuBarExtra).
struct MenuBarContentView: View {
    var store: PaperStore
    let closePopover: () -> Void

    private static let popoverWidth: CGFloat = 360

    private var recommendedPapers: [Paper] {
        store.papers.filter { paper in
            paper.isRecommended && paper.recommendedAt.map { Calendar.current.isDateInToday($0) } == true
        }
    }

    private var dateString: String {
        Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
        .frame(width: Self.popoverWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(.todaysTopPicks))
                    .font(.system(size: 13, weight: .semibold))
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !recommendedPapers.isEmpty {
                Text("\(recommendedPapers.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if recommendedPapers.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(recommendedPapers.enumerated()), id: \.element.id) { index, paper in
                        MenuBarPaperRow(
                            rank: index + 1,
                            paper: paper,
                            onStar: { setStatus(paper, .starred) },
                            onRead: { setStatus(paper, .read) },
                            onSkip: { setStatus(paper, .skip) },
                            onCancelRecommendation: { cancelRecommendation(paper) },
                            onOpenPdf: { openPdf(for: paper) },
                            onOpenInApp: { openMainWindow(paperId: paper.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 360)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text(L10n.t(.noRecommendations))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(L10n.t(.runRecommendEngine)) { runRecommendEngine() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { openMainWindow() } label: {
                Label(L10n.t(.openVellumX), systemImage: "macwindow")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.82))
            }
            .buttonStyle(.plain)

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                Label(L10n.t(.quit), systemImage: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.62))
            }
            .buttonStyle(.plain)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func setStatus(_ paper: Paper, _ status: PaperStatus) {
        withAnimation(.easeOut(duration: 0.18)) {
            store.setPaperStatus(id: paper.id, status: status)
        }
    }

    private func cancelRecommendation(_ paper: Paper) {
        withAnimation(.easeOut(duration: 0.18)) {
            store.setPaperRecommended(id: paper.id, isRecommended: false)
        }
    }

    private func runRecommendEngine() {
        Task {
            _ = await PaperWorkflowService.shared.recommendPapers()
        }
    }

    /// Bring the main window to the front (activating the app), then dismiss
    /// the popover. Uses SwiftUI's openWindow action (captured by the App) so a
    /// closed WindowGroup window is recreated rather than just re-fronted.
    private func openMainWindow(paperId: String? = nil) {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        MainWindowOpener.shared.open(paperId: paperId)
    }

    private func openPdf(for paper: Paper) {
        Task {
            if PdfCoordinator.hasLocalPdf(paper) {
                await PdfCoordinator.reveal(paper: paper, store: store)
            } else {
                await PdfCoordinator.fetch(paper: paper, store: store)
            }
        }
    }
}

/// A single recommendation row. The whole card is a button that opens the
/// paper's detail in the main window; star / read / PDF and other quick actions
/// live in the right-click context menu.
private struct MenuBarPaperRow: View {
    let rank: Int
    let paper: Paper
    let onStar: () -> Void
    let onRead: () -> Void
    let onSkip: () -> Void
    let onCancelRecommendation: () -> Void
    let onOpenPdf: () -> Void
    let onOpenInApp: () -> Void

    @State private var isHovering = false

    private var meta: String {
        var parts: [String] = []
        let venue = paper.venueAbbr.isEmpty ? paper.venue : paper.venueAbbr
        if !venue.isEmpty { parts.append(venue) }
        if paper.citedByCount > 0 { parts.append("\(paper.citedByCount) cites") }
        if let year = paper.publicationYear {
            parts.append(String(year))
        } else if !paper.publicationDate.isEmpty {
            parts.append(paper.publicationDate)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onOpenInApp) {
            HStack(alignment: .top, spacing: 9) {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(isHovering ? Color.accentColor.opacity(0.14)
                                                  : Color.primary.opacity(0.05))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        if paper.score > 0 {
                            TagChip.score(paper.score,
                                          color: MetadataStore.shared.tierColor(paper.tier))
                        }
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Hover affordance: the whole card opens the paper's detail.
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            Button { onStar() } label: { Label(L10n.t(.markStarred), systemImage: "star") }
            Button { onRead() } label: { Label(L10n.t(.markRead), systemImage: "checkmark.circle") }
            Button { onOpenPdf() } label: { Label(L10n.t(.openPDF), systemImage: "doc.text") }
            Divider()
            Button { onOpenInApp() } label: { Label(L10n.t(.openInVellumX), systemImage: "macwindow") }
            Button { onCancelRecommendation() } label: { Label(L10n.t(.cancelRecommendation), systemImage: "xmark.circle") }
            Divider()
            Button { onSkip() } label: { Label(L10n.t(.markSkip), systemImage: "eye.slash") }
        }
    }
}
