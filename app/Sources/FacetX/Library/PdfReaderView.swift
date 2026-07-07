import PDFKit
import SwiftUI

/// In-app PDF reader backing the literature "Reading" view. Owns a single live
/// `PDFView` so the toolbar can drive it imperatively (paging, zoom, find) while
/// SwiftUI observes `currentPage` / `pageCount` for the page indicator.
@MainActor
@Observable
final class PdfReaderModel {
    @ObservationIgnored let pdfView: FacetPDFView
    var currentPage = 1
    var pageCount = 0
    var hasSelection = false
    var selectionText = ""
    var activeAnnotation: PDFAnnotation? = nil
    var outlineItems: [PdfOutlineItem] = []
    var annotations: [PdfAnnotationItem] = []

    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private let pageObserver = PageObserver()
    @ObservationIgnored private let selectionObserver = SelectionObserver()

    init() {
        let view = FacetPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
        pdfView = view
        view.model = self
        pageObserver.onChange = { [weak self] in self?.syncCurrentPage() }
        pageObserver.observe(view)
        selectionObserver.onChange = { [weak self] in self?.syncSelection() }
        selectionObserver.observe(view)
    }

    /// Loads `url` into the view, no-op when it's already the current document.
    func load(url: URL) {
        guard url != loadedURL else { return }
        loadedURL = url
        let document = PDFDocument(url: url)
        pdfView.document = document
        pageCount = document?.pageCount ?? 0
        currentPage = 1
        hasSelection = false
        selectionText = ""
        activeAnnotation = nil
        loadOutline()
        loadAnnotations()
        if let first = document?.page(at: 0) { pdfView.go(to: first) }
    }

    func clear() {
        loadedURL = nil
        pdfView.document = nil
        pageCount = 0
        currentPage = 1
        hasSelection = false
        selectionText = ""
        activeAnnotation = nil
        outlineItems = []
        annotations = []
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

    private func syncSelection() {
        selectionText = pdfView.currentSelection?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasSelection = !selectionText.isEmpty
    }

    // MARK: - Outline Operations

    func loadOutline() {
        outlineItems = []
        guard let document = pdfView.document,
              let root = document.outlineRoot else { return }
        traverseOutline(root, depth: 0)
    }

    private func traverseOutline(_ outline: PDFOutline, depth: Int) {
        for i in 0..<outline.numberOfChildren {
            if let child = outline.child(at: i) {
                if let title = child.label, let dest = child.destination {
                    outlineItems.append(PdfOutlineItem(title: title, depth: depth, destination: dest))
                }
                traverseOutline(child, depth: depth + 1)
            }
        }
    }

    func loadAnnotations() {
        annotations = []
        guard let document = pdfView.document else { return }
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for ann in page.annotations {
                if ann.type == "Highlight" {
                    let text = ann.contents ?? L10n.pick("Highlight", "高亮")
                    annotations.append(PdfAnnotationItem(
                        type: "Highlight",
                        color: Color(nsColor: ann.color),
                        text: text,
                        pageIndex: i,
                        annotation: ann
                    ))
                } else if ann.type == "Text" {
                    let text = ann.contents ?? L10n.pick("Sticky Note", "便签批注")
                    annotations.append(PdfAnnotationItem(
                        type: "Note",
                        color: Color(nsColor: ann.color),
                        text: text.isEmpty ? L10n.pick("[Empty note]", "[空白批注]") : text,
                        pageIndex: i,
                        annotation: ann
                    ))
                }
            }
        }
    }

    // MARK: - Annotation Operations

    func saveDocument() {
        guard let document = pdfView.document, let url = loadedURL else { return }
        document.write(to: url)
        loadAnnotations()
    }

    func highlightCurrentSelection(color: NSColor) {
        guard let selection = pdfView.currentSelection else { return }
        
        let lineSelections = selection.selectionsByLine()
        for line in lineSelections {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                page.addAnnotation(annotation)
            }
        }
        
        saveDocument()
        pdfView.clearSelection()
        hasSelection = false
        selectionText = ""
        
        // Force redraw of PDFView to reflect the added annotation
        pdfView.layoutDocumentView()
    }

    func addNoteToSelection() {
        guard let selection = pdfView.currentSelection,
              let page = selection.pages.first else { return }
        
        // Highlight the selected text lines under the note
        let lineSelections = selection.selectionsByLine()
        for line in lineSelections {
            for linePage in line.pages {
                let lineBounds = line.bounds(for: linePage)
                let highlight = PDFAnnotation(bounds: lineBounds, forType: .highlight, withProperties: nil)
                highlight.color = .systemYellow
                linePage.addAnnotation(highlight)
            }
        }
        
        // Position the note bubble near the top-right of the selection bounds
        let bounds = selection.bounds(for: page)
        let noteBounds = CGRect(x: bounds.maxX + 4, y: bounds.maxY - 12, width: 20, height: 20)
        let annotation = PDFAnnotation(bounds: noteBounds, forType: .text, withProperties: nil)
        annotation.color = .systemYellow
        annotation.contents = ""
        
        page.addAnnotation(annotation)
        saveDocument()
        
        // Select the new annotation in our model so it can be managed or deleted
        activeAnnotation = annotation
        pdfView.clearSelection()
        hasSelection = false
        selectionText = ""
        
        pdfView.layoutDocumentView()
    }

    func deleteActiveAnnotation() {
        guard let annotation = activeAnnotation else { return }
        let page = annotation.page
        page?.removeAnnotation(annotation)
        saveDocument()
        activeAnnotation = nil
        
        pdfView.layoutDocumentView()
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

/// Bridges `PDFView`'s selection-changed notification to a closure.
@MainActor
private final class SelectionObserver: NSObject {
    var onChange: () -> Void = {}

    func observe(_ pdfView: PDFView) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionChanged),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
    }

    @objc private func selectionChanged() { onChange() }

    deinit { NotificationCenter.default.removeObserver(self) }
}

/// A subclass of `PDFView` that captures activeAnnotation changes and intercepts
/// key events to support Delete (Backspace) of selected annotations.
@MainActor
final class FacetPDFView: PDFView {
    weak var model: PdfReaderModel?

    override func keyDown(with event: NSEvent) {
        // keycode 51 is Backspace, 117 is Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            if let model = model, let annotation = model.activeAnnotation {
                let page = annotation.page
                page?.removeAnnotation(annotation)
                model.saveDocument()
                model.activeAnnotation = nil
                layoutDocumentView()
                return
            }
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        // After default click handling, check if an annotation was hit
        let point = convert(event.locationInWindow, from: nil)
        if let page = page(for: point, nearest: false) {
            let pagePoint = convert(point, to: page)
            let annotation = page.annotation(at: pagePoint)
            model?.activeAnnotation = annotation
        } else {
            model?.activeAnnotation = nil
        }
    }
}

/// Hosts the model's live `PDFView` in SwiftUI. The view is created once and
/// owned by the model, so updates are driven through the model, not by rebuilds.
struct PdfReaderRepresentable: NSViewRepresentable {
    let model: PdfReaderModel

    func makeNSView(context: Context) -> PDFView { model.pdfView }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

/// Supported highlight colors for PDF annotations.
enum PdfHighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .pink:   return .pink
        case .purple: return .purple
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .blue:   return .systemBlue
        case .pink:   return .systemPink
        case .purple: return .systemPurple
        }
    }

    var displayName: String {
        switch self {
        case .yellow: return L10n.pick("Yellow Highlight", "黄色高亮")
        case .green:  return L10n.pick("Green Highlight", "绿色高亮")
        case .blue:   return L10n.pick("Blue Highlight", "蓝色高亮")
        case .pink:   return L10n.pick("Pink Highlight", "粉色高亮")
        case .purple: return L10n.pick("Purple Highlight", "紫色高亮")
        }
    }
}

/// Represents a single navigable entry in the PDF table of contents.
struct PdfOutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let depth: Int
    let destination: PDFDestination
}

/// Represents an annotation summary displayed in the sidebar.
struct PdfAnnotationItem: Identifiable {
    let id = UUID()
    let type: String // "Highlight" or "Note"
    let color: Color
    let text: String
    let pageIndex: Int
    let annotation: PDFAnnotation
}
