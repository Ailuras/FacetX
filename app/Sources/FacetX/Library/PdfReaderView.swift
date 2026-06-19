import PDFKit
import SwiftUI

/// In-app PDF reader backing the literature "Reading" view. Owns a single live
/// `PDFView` so the toolbar can drive it imperatively (paging, zoom, find) while
/// SwiftUI observes `currentPage` / `pageCount` for the page indicator.
@MainActor
@Observable
final class PdfReaderModel {
    @ObservationIgnored let pdfView: PDFView
    var currentPage = 1
    var pageCount = 0

    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private let pageObserver = PageObserver()

    init() {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
        pdfView = view
        pageObserver.onChange = { [weak self] in self?.syncCurrentPage() }
        pageObserver.observe(view)
    }

    /// Loads `url` into the view, no-op when it's already the current document.
    func load(url: URL) {
        guard url != loadedURL else { return }
        loadedURL = url
        let document = PDFDocument(url: url)
        pdfView.document = document
        pageCount = document?.pageCount ?? 0
        currentPage = 1
        if let first = document?.page(at: 0) { pdfView.go(to: first) }
    }

    func clear() {
        loadedURL = nil
        pdfView.document = nil
        pageCount = 0
        currentPage = 1
    }

    func nextPage() { pdfView.goToNextPage(nil) }
    func previousPage() { pdfView.goToPreviousPage(nil) }

    func zoomIn() {
        pdfView.autoScales = false
        pdfView.scaleFactor = min(pdfView.scaleFactor * 1.2, pdfView.maxScaleFactor)
    }

    func zoomOut() {
        pdfView.autoScales = false
        pdfView.scaleFactor = max(pdfView.scaleFactor / 1.2, pdfView.minScaleFactor)
    }

    func fitWidth() { pdfView.autoScales = true }

    /// Finds the next occurrence of `text` from the current selection, wrapping
    /// to the start when there's nothing further, and scrolls it into view.
    func find(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let document = pdfView.document else { return }
        let next = document.findString(trimmed, fromSelection: pdfView.currentSelection, withOptions: [.caseInsensitive])
            ?? document.findString(trimmed, fromSelection: nil, withOptions: [.caseInsensitive])
        guard let selection = next else { return }
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.scrollSelectionToVisible(nil)
    }

    private func syncCurrentPage() {
        guard let page = pdfView.currentPage, let document = pdfView.document else { return }
        currentPage = document.index(for: page) + 1
    }
}

/// Bridges `PDFView`'s page-changed notification to a closure using the same
/// `@MainActor` NSObject + `@objc` selector pattern as `ToolbarSearchField`,
/// keeping it clean under Swift 6 strict concurrency.
@MainActor
private final class PageObserver: NSObject {
    var onChange: () -> Void = {}

    func observe(_ pdfView: PDFView) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    @objc private func pageChanged() { onChange() }

    deinit { NotificationCenter.default.removeObserver(self) }
}

/// Hosts the model's live `PDFView` in SwiftUI. The view is created once and
/// owned by the model, so updates are driven through the model, not by rebuilds.
struct PdfReaderRepresentable: NSViewRepresentable {
    let model: PdfReaderModel

    func makeNSView(context: Context) -> PDFView { model.pdfView }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}
