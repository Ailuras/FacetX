import WebKit

class MarkdownPDFExporter: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var text: String = ""
    private var completion: ((Result<Data, Error>) -> Void)?
    private var keepAlive: MarkdownPDFExporter?

    func export(text: String, completion: @escaping (Result<Data, Error>) -> Void) {
        self.text = text
        self.completion = completion
        self.keepAlive = self // Keep self alive during async operations

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "facetx")
        config.userContentController = controller

        // Create web view with a reasonable A4 page size frame
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "MarkdownPreview") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        } else {
            cleanup(result: .failure(NSError(domain: "PDFExporter", code: 404, userInfo: [NSLocalizedDescriptionKey: "MarkdownPreview template not found"])))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              body["type"] as? String == "ready",
              let webView = self.webView else { return }

        // Set content and force light theme for clean PDF print/export
        let jsonText = jsString(text)
        webView.evaluateJavaScript("window.FacetXPreview.setTheme('light'); window.FacetXPreview.setContent(\(jsonText));") { _, error in
            if let error = error {
                self.cleanup(result: .failure(error))
                return
            }
            
            // Give a short delay for layout to settle (like KaTeX math rendering)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let pdfConfig = WKPDFConfiguration()
                webView.createPDF(configuration: pdfConfig) { result in
                    self.cleanup(result: result)
                }
            }
        }
    }

    private func cleanup(result: Result<Data, Error>) {
        completion?(result)
        webView = nil
        completion = nil
        keepAlive = nil
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }
}
