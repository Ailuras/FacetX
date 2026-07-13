import SwiftUI
import WebKit

/// A read-only markdown preview rendered by markdown-it + KaTeX in a `WKWebView`.
/// The prebuilt web bundle lives in `Resources/MarkdownPreview` (built from
/// `web/note-editor`). The view is display-only: editing happens in the native
/// `MarkdownEditor`; this just re-renders whenever `text` changes.
///
/// `variant` selects the bundle's CSS: `"note"` is the full-page preview used
/// by document previews; `"chat"` is a padding-free style meant to be dropped
/// into a native chat bubble. When `onHeightChange` is set, the page reports
/// its rendered content height so the SwiftUI side can size the bubble to fit
/// instead of relying on the WebView's own (disabled) scrolling.
struct MarkdownPreviewWeb: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    var variant: String = "note"
    var fullWidth: Bool = false
    var onHeightChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "facetx")

        // Inject CSS to hide the WebKit scrollbar. The subview-walk approach fails
        // because WKScrollView is a private class that doesn't cast to NSScrollView.
        let hideScrollbarCSS = """
            ::-webkit-scrollbar { display: none !important; }
            """
        let script = WKUserScript(source: """
            (function() {
              var style = document.createElement('style');
              style.textContent = '\(hideScrollbarCSS)';
              document.head.appendChild(style);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true)
        controller.addUserScript(script)
        config.userContentController = controller

        let webView = PassThroughWebView(frame: .zero, configuration: config)
        webView.shouldPassThroughScroll = (onHeightChange != nil)
        webView.setValue(false, forKey: "drawsBackground") // blend with the native pane
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let index = Self.bundleURL {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let webView = nsView as? PassThroughWebView {
            webView.shouldPassThroughScroll = (onHeightChange != nil)
        }
        context.coordinator.pendingText = text
        context.coordinator.variant = variant
        context.coordinator.fullWidth = fullWidth
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.colorScheme = colorScheme
        context.coordinator.applyTheme()
        context.coordinator.render() // no-op until the page signals it is ready
        context.coordinator.applyFullWidth()
    }

    private static var bundleURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "MarkdownPreview")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false
        var pendingText = ""
        var variant = "note"
        var fullWidth = false
        var colorScheme: ColorScheme = .light
        var onHeightChange: ((CGFloat) -> Void)?
        private var renderedText: String?
        private var renderedVariant: String?

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                isReady = true
                applyTheme()
                applyFullWidth()
                renderedText = nil // force the first render
                render()
            case "height":
                if let value = body["value"] as? NSNumber {
                    onHeightChange?(CGFloat(truncating: value))
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            renderedText = nil
            applyTheme()
            applyFullWidth()
            render()
        }

        /// Push the current markdown to the renderer if it changed.
        func render() {
            guard isReady, let webView,
                  pendingText != renderedText || variant != renderedVariant else { return }
            renderedText = pendingText
            renderedVariant = variant
            let json = Self.jsString(pendingText)
            webView.evaluateJavaScript("window.FacetXPreview.setContent(\(json), '\(variant)');")
        }

        func applyTheme() {
            guard isReady, let webView else { return }
            let isDark = colorScheme == .dark
            webView.evaluateJavaScript("window.FacetXPreview.setTheme('\(isDark ? "dark" : "light")');")
        }

        func applyFullWidth() {
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.FacetXPreview.setFullWidth(\(fullWidth ? "true" : "false"));")
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
            return literal
        }
    }
}

private final class PassThroughWebView: WKWebView {
    var shouldPassThroughScroll = false

    override func scrollWheel(with event: NSEvent) {
        if shouldPassThroughScroll {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
