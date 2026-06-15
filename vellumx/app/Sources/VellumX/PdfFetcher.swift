import Foundation

/// Turns candidate links into a stored PDF: downloads each candidate, keeps the
/// first whose bytes validate as a real PDF, and writes it to local storage.
/// Network + filesystem only — no UI, no app state, no opening. Content parsing
/// (full text, in-app reader) is intentionally out of scope for this phase.
struct PdfFetcher {
    let config: AppConfig
    let storage: PdfStorage

    /// Downloads and validates a paper's PDF. Returns the materialized result;
    /// the caller is responsible for persisting it via `PaperStore.savePdf`.
    func fetch(id: String, title: String, doi: String?, currentPdfUrl: String?) async -> PdfFetchResult {
        let resolver = PdfResolver(config: config)
        let candidates = await resolver.candidates(title: title, doi: doi, currentPdfUrl: currentPdfUrl)
        if candidates.isEmpty { return .dead }

        var firstUrl: String?
        var firstSource: String?
        for candidate in candidates {
            guard let url = URL(string: candidate.url) else { continue }
            if firstUrl == nil { firstUrl = candidate.url; firstSource = candidate.source }
            guard let data = await Self.download(url) else { continue }
            guard PdfStorage.looksLikePdf(data) else { continue }

            do {
                let relative = try storage.write(data, forPaperId: id)
                return PdfFetchResult(
                    status: .downloaded,
                    url: candidate.url,
                    source: candidate.source,
                    localPath: relative,
                    byteSize: data.count,
                    sha256: PdfStorage.sha256Hex(data)
                )
            } catch {
                print("PDF write failed: \(error)")
            }
        }

        // Candidates existed but none was a real PDF (landing page / paywall).
        if let firstUrl, let firstSource {
            return .notPdf(url: firstUrl, source: firstSource)
        }
        return .dead
    }

    private static func download(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            print("PDF download failed for \(url): \(error)")
            return nil
        }
    }
}
