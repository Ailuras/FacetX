import SwiftUI
import WebKit

/// A WYSIWYG markdown note editor backed by Milkdown (Crepe) + KaTeX, hosted in a
/// `WKWebView`. The prebuilt web bundle lives in `Resources/NoteEditor` (built
/// from `web/note-editor`). Markdown stays the source of truth: the web editor
/// reports debounced changes back through `text`, and `documentID` drives when a
/// fresh document is pushed into the editor (i.e. when the user switches notes).
struct MilkdownNoteEditor: NSViewRepresentable {
    @Binding var text: String
    /// Stable identity of the loaded note. Changing it re-seeds the web editor.
    let documentID: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "facetx")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // blend with the native pane
        webView.navigationDelegate = context.coordinator
        // Inspectable so the editor can be debugged via Safari Web Inspector
        // (right-click → Inspect Element). Revisit before shipping.
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        context.coordinator.webView = webView

        if let index = Self.bundleURL {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Push a new document only when the note actually changed, so the
        // editor's own edits (which flow back via `text`) don't reload it.
        if context.coordinator.isReady, context.coordinator.loadedDocumentID != documentID {
            context.coordinator.pushContent()
        }
        context.coordinator.applyTheme()
    }

    private static var bundleURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "NoteEditor")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MilkdownNoteEditor
        weak var webView: WKWebView?
        var isReady = false
        var loadedDocumentID: String?

        init(_ parent: MilkdownNoteEditor) { self.parent = parent }

        // ── JS → native ─────────────────────────────────────────────────────────

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                isReady = true
                applyTheme()
                pushContent()
            case "change":
                if let markdown = body["markdown"] as? String {
                    parent.text = markdown
                }
            default:
                break
            }
        }

        // ── native → JS ─────────────────────────────────────────────────────────

        /// Seed the web editor with the current note's markdown.
        func pushContent() {
            guard isReady, let webView else { return }
            loadedDocumentID = parent.documentID
            let json = Self.jsString(parent.text)
            webView.evaluateJavaScript("window.FacetXEditor.setContent(\(json));")
        }

        func applyTheme() {
            guard isReady, let webView else { return }
            let isDark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            webView.evaluateJavaScript("window.FacetXEditor.setTheme('\(isDark ? "dark" : "light")');")
        }

        /// JSON-encode a Swift string into a safe JS string literal (quotes included).
        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
            return literal
        }
    }
}
