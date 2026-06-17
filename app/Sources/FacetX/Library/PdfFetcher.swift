import Foundation

/// Turns candidate PDF links into one validated local PDF.
struct PdfFetcher {
    let config: AppConfig
    let storage: PdfStorage

    func fetch(id: String, title: String, doi: String?, currentPdfUrl: String?) async -> PdfFetchResult {
        let resolver = PdfResolver(config: config)
        let candidates = await resolver.candidates(title: title, doi: doi, currentPdfUrl: currentPdfUrl)
        guard !candidates.isEmpty else { return .dead }

        var firstUrl: String?
        var firstSource: String?
        for candidate in candidates {
            guard let url = URL(string: candidate.url) else { continue }
            if firstUrl == nil {
                firstUrl = candidate.url
                firstSource = candidate.source
            }
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
