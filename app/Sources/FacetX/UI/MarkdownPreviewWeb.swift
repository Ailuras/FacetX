import SwiftUI
import WebKit

/// A read-only markdown preview rendered by markdown-it + KaTeX in a `WKWebView`.
/// The prebuilt web bundle lives in `Resources/NotePreview` (built from
/// `web/note-editor`). The view is display-only: editing happens in the native
/// `MarkdownEditor`; this just re-renders whenever `text` changes.
struct MarkdownPreviewWeb: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "facetx")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // blend with the native pane
        context.coordinator.webView = webView

        if let index = Self.bundleURL {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingText = text
        context.coordinator.render() // no-op until the page signals it is ready
    }

    private static var bundleURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "NotePreview")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var isReady = false
        var pendingText = ""
        private var renderedText: String?

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "ready" else { return }
            isReady = true
            applyTheme()
            renderedText = nil // force the first render
            render()
        }

        /// Push the current markdown to the renderer if it changed.
        func render() {
            guard isReady, let webView, pendingText != renderedText else { return }
            renderedText = pendingText
            let json = Self.jsString(pendingText)
            webView.evaluateJavaScript("window.FacetXPreview.setContent(\(json));")
        }

        func applyTheme() {
            guard isReady, let webView else { return }
            let isDark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            webView.evaluateJavaScript("window.FacetXPreview.setTheme('\(isDark ? "dark" : "light")');")
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
            return literal
        }
    }
}
