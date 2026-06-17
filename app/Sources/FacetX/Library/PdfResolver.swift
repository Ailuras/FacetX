import Foundation

/// Resolves candidate open-access PDF links. Network-only: downloads and
/// persistence stay in `PdfFetcher`.
final class PdfResolver {
    let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    private func fetchUnpaywall(doi: String) async -> String? {
        let email = config.openalex.mailto
        guard !email.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.unpaywall.org/v2/\(doi)")
        components?.queryItems = [URLQueryItem(name: "email", value: email)]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            struct Location: Decodable {
                var urlForPdf: String?
                var url: String?
                enum CodingKeys: String, CodingKey {
                    case urlForPdf = "url_for_pdf"
                    case url
                }
            }
            struct Response: Decodable {
                var isOA: Bool?
                var bestOALocation: Location?
                enum CodingKeys: String, CodingKey {
                    case isOA = "is_oa"
                    case bestOALocation = "best_oa_location"
                }
            }

            let result = try JSONDecoder().decode(Response.self, from: data)
            if result.isOA == true {
                return result.bestOALocation?.urlForPdf ?? result.bestOALocation?.url
            }
        } catch {
            print("Unpaywall lookup failed: \(error)")
        }
        return nil
    }

    private func fetchArxiv(title: String) async -> String? {
        guard !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://export.arxiv.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: "ti:\"\(title)\""),
            URLQueryItem(name: "max_results", value: "3"),
            URLQueryItem(name: "sortBy", value: "relevance")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8) else { return nil }

            let regex = try NSRegularExpression(pattern: "<id>http://arxiv.org/abs/(.+?)</id>")
            let range = NSRange(location: 0, length: xml.utf16.count)
            guard let match = regex.firstMatch(in: xml, range: range),
                  let idRange = Range(match.range(at: 1), in: xml) else { return nil }
            return "https://arxiv.org/pdf/\(String(xml[idRange])).pdf"
        } catch {
            print("arXiv lookup failed: \(error)")
            return nil
        }
    }

    private func fetchSemanticScholar(doi: String) async -> String? {
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/DOI:\(doi)")
        components?.queryItems = [URLQueryItem(name: "fields", value: "openAccessPdf")]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            struct OpenAccessPdf: Decodable { var url: String? }
            struct Response: Decodable { var openAccessPdf: OpenAccessPdf? }
            return try JSONDecoder().decode(Response.self, from: data).openAccessPdf?.url
        } catch {
            print("Semantic Scholar lookup failed: \(error)")
            return nil
        }
    }

    func candidates(title: String, doi: String?, currentPdfUrl: String?) async -> [(url: String, source: String)] {
        var result: [(url: String, source: String)] = []

        if let currentPdfUrl, !currentPdfUrl.isEmpty {
            result.append((currentPdfUrl, "openalex"))
        }

        let bareDoi = doi.map(Self.stripDoiPrefix).flatMap { $0.isEmpty ? nil : $0 }

        if let bareDoi, let url = await fetchUnpaywall(doi: bareDoi) {
            result.append((url, "unpaywall"))
        }
        if let url = await fetchArxiv(title: title) {
            result.append((url, "arxiv"))
        }
        if let bareDoi, let url = await fetchSemanticScholar(doi: bareDoi) {
            result.append((url, "semanticscholar"))
        }

        return result
    }

    static func stripDoiPrefix(_ doi: String) -> String {
        let lower = doi.lowercased()
        for prefix in ["https://doi.org/", "http://doi.org/",
                       "https://dx.doi.org/", "http://dx.doi.org/"] {
            if lower.hasPrefix(prefix) {
                return String(doi.dropFirst(prefix.count))
            }
        }
        return doi
    }
}
