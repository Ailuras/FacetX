import SwiftUI
import WebKit

struct GoogleScholarWebView: NSViewRepresentable {
    let query: String
    let importedTitles: Set<String>
    let onImport: ([String: Any]) -> Void
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: GoogleScholarWebView
        var webView: WKWebView?
        var lastLoadedValue: String? = nil
        
        init(_ parent: GoogleScholarWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "facetxImport",
                  let dict = message.body as? [String: Any] else { return }
            parent.onImport(dict)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Apply current appearance theme (dark/light) to the page
            updateTheme(webView)
            updateImportStatus(webView)
        }
        
        func updateTheme(_ webView: WKWebView) {
            let isDark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            
            let darkThemeCss = """
            body { background-color: #1e1e1e !important; color: #e0e0e0 !important; }
            #gs_bdy { background-color: #1e1e1e !important; }
            #gs_hdr { background-color: #2d2d2d !important; border-bottom: 1px solid #3d3d3d !important; }
            #gs_hdr_hp { background-color: #1e1e1e !important; }
            .gs_rt a:link, .gs_rt a:visited { color: #8ab4f8 !important; }
            .gs_a { color: #a8a8a8 !important; }
            .gs_rs { color: #cccccc !important; }
            .gs_fl a:link, .gs_fl a:visited { color: #8ab4f8 !important; }
            #gs_ab_rt { color: #a8a8a8 !important; }
            .gs_md_wp { background-color: #2d2d2d !important; border: 1px solid #3d3d3d !important; }
            .gs_n a:link, .gs_n a:visited { color: #8ab4f8 !important; }
            """
            let commonCss = """
            /* Hide footers, sidebars and headers for cleaner integration */
            #gs_ftr, #gs_hp_ftr, #gs_bdy_sb, #gs_hp_hdr { display: none !important; }
            #gs_bdy_ccl { margin-left: 20px !important; }
            
            /* Custom button styles */
            .facetx-import-btn {
                margin-left: 8px;
                padding: 0 6px;
                height: 18px;
                line-height: 18px;
                background-color: #007AFF;
                color: #FFFFFF !important;
                border: none;
                border-radius: 3px;
                cursor: pointer;
                font-weight: 500;
                font-size: 10px;
                display: inline-flex;
                align-items: center;
                vertical-align: middle;
            }
            .facetx-import-btn:hover {
                background-color: #0063CC;
            }
            .facetx-import-btn:disabled {
                background-color: #34C759;
                color: #FFFFFF !important;
                cursor: default;
            }
            """
            
            let activeCss = isDark ? (commonCss + "\n" + darkThemeCss) : commonCss
            
            let js = """
            (function() {
                var existingStyle = document.getElementById('facetx-custom-style');
                if (existingStyle) {
                    existingStyle.textContent = `\(activeCss)`;
                } else {
                    var style = document.createElement('style');
                    style.id = 'facetx-custom-style';
                    style.textContent = `\(activeCss)`;
                    document.head.appendChild(style);
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func updateImportStatus(_ webView: WKWebView) {
            let titlesArray = Array(parent.importedTitles)
            guard let jsonArray = try? JSONSerialization.data(withJSONObject: titlesArray, options: [.fragmentsAllowed]),
                  let jsonString = String(data: jsonArray, encoding: .utf8) else { return }
            
            let js = """
            (function() {
                var imported = \(jsonString);
                var buttons = document.querySelectorAll('.facetx-import-btn');
                buttons.forEach(function(btn) {
                    var row = btn.closest('.gs_r.gs_or.gs_scl');
                    if (row) {
                        var titleEl = row.querySelector('.gs_rt a');
                        if (titleEl) {
                            var title = titleEl.innerText.trim();
                            if (imported.some(function(t) { return t.toLowerCase() === title.toLowerCase(); })) {
                                btn.innerText = '✓ 已导入';
                                btn.style.backgroundColor = '#34C759';
                                btn.disabled = true;
                            }
                        }
                    }
                });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "facetxImport")
        
        let jsSource = """
        function injectFacetXButtons() {
            var results = document.querySelectorAll('.gs_r.gs_or.gs_scl');
            results.forEach(function(row) {
                if (row.querySelector('.facetx-import-btn')) return;
                
                var titleEl = row.querySelector('.gs_rt a');
                if (!titleEl) return;
                
                var btn = document.createElement('button');
                btn.className = 'facetx-import-btn';
                btn.innerText = '＋ 导入';
                
                btn.onclick = function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    
                    var title = titleEl.innerText.trim();
                    var link = titleEl.href;
                    var metaEl = row.querySelector('.gs_a');
                    var metaText = metaEl ? metaEl.innerText.trim() : "";
                    var snippetEl = row.querySelector('.gs_rs');
                    var snippet = snippetEl ? snippetEl.innerText.trim() : "";
                    var pdfEl = row.querySelector('.gs_or_gg a, .gs_ggsd a');
                    var pdfUrl = pdfEl ? pdfEl.href : null;
                    
                    var parts = metaText.split(' - ');
                    var authors = parts[0] ? parts[0].split(',').map(function(s) { return s.trim(); }) : [];
                    var year = null;
                    var venue = "";
                    if (parts[1]) {
                        venue = parts[1];
                        var yearMatch = parts[1].match(/\\d{4}/);
                        if (yearMatch) {
                            year = parseInt(yearMatch[0]);
                        }
                    }
                    
                    var payload = {
                        title: title,
                        url: link,
                        authors: authors,
                        venue: venue,
                        year: year,
                        snippet: snippet,
                        pdfUrl: pdfUrl
                    };
                    
                    window.webkit.messageHandlers.facetxImport.postMessage(payload);
                };
                
                titleEl.parentNode.appendChild(btn);
            });
        }
        
        // Polling to handle dynamically loaded content
        setInterval(injectFacetXButtons, 1000);
        """
        
        let userScript = WKUserScript(
            source: jsSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(userScript)
        
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        
        // Enable back/forward swipes
        webView.allowsBackForwardNavigationGestures = true
        
        context.coordinator.lastLoadedValue = query
        loadQuery(in: webView)
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateTheme(nsView)
        context.coordinator.updateImportStatus(nsView)
        
        if context.coordinator.lastLoadedValue != query {
            context.coordinator.lastLoadedValue = query
            loadQuery(in: nsView)
        }
    }
    
    private func loadQuery(in webView: WKWebView) {
        let urlString: String
        if query.hasPrefix("http://") || query.hasPrefix("https://") {
            urlString = query
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urlString = "https://scholar.google.com/"
        } else if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = "https://scholar.google.com/scholar?q=\(encoded)"
        } else {
            urlString = "https://scholar.google.com/"
        }
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
}
