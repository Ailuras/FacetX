import Foundation

// MARK: - OpenAlex API DTOs

struct OpenAlexSource: Decodable {
    var displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

struct OpenAlexLocation: Decodable {
    var source: OpenAlexSource?
    var landingPageUrl: String?
    var pdfUrl: String?
    enum CodingKeys: String, CodingKey {
        case source
        case landingPageUrl = "landing_page_url"
        case pdfUrl = "pdf_url"
    }
}

struct OpenAlexAuthor: Decodable {
    var displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

struct OpenAlexAuthorship: Decodable {
    var author: OpenAlexAuthor?
}

struct OpenAlexOpenAccess: Decodable {
    var oaUrl: String?
    enum CodingKeys: String, CodingKey { case oaUrl = "oa_url" }
}

struct OpenAlexWork: Decodable {
    var id: String
    var doi: String?
    var title: String?
    var displayName: String?
    var authorships: [OpenAlexAuthorship]?
    var publicationYear: Int?
    var publicationDate: String?
    var citedByCount: Int?
    var abstractInvertedIndex: [String: [Int]]?
    var primaryLocation: OpenAlexLocation?
    var openAccess: OpenAlexOpenAccess?
    var relatedWorks: [String]?

    enum CodingKeys: String, CodingKey {
        case id, doi, title, authorships
        case displayName = "display_name"
        case publicationYear = "publication_year"
        case publicationDate = "publication_date"
        case citedByCount = "cited_by_count"
        case abstractInvertedIndex = "abstract_inverted_index"
        case primaryLocation = "primary_location"
        case openAccess = "open_access"
        case relatedWorks = "related_works"
    }
}

struct OpenAlexMeta: Decodable {
    var nextCursor: String?
    enum CodingKeys: String, CodingKey { case nextCursor = "next_cursor" }
}

struct OpenAlexResponse: Decodable {
    var meta: OpenAlexMeta?
    var results: [OpenAlexWork]?
}

// MARK: - Fetcher Class

class OpenAlexFetcher: @unchecked Sendable {
    let config: AppConfig
    let scorer: VenueScorer

    struct FetchFailure {
        var trackName: String
        var error: Error
    }

    enum FetchError: LocalizedError {
        case allTracksFailed([FetchFailure])

        var errorDescription: String? {
            switch self {
            case .allTracksFailed(let failures):
                let names = failures.map(\.trackName).joined(separator: ", ")
                return "All OpenAlex track fetches failed: \(names)"
            }
        }
    }

    init(config: AppConfig, venues: [VenuePref] = []) {
        self.config = config
        self.scorer = VenueScorer(config: config, venues: venues)
    }

    private func restoreAbstract(from index: [String: [Int]]?) -> String {
        guard let index = index else { return "" }
        var wordsList: [(Int, String)] = []
        for (word, positions) in index {
            for pos in positions {
                wordsList.append((pos, word))
            }
        }
        wordsList.sort { $0.0 < $1.0 }
        return wordsList.map { $0.1 }.joined(separator: " ")
    }

    private func parseWork(_ work: OpenAlexWork, track: String) -> Paper {
        let venue = work.primaryLocation?.source?.displayName ?? ""
        let citations = work.citedByCount ?? 0
        let (tier, venueAbbr, score) = scorer.evaluate(venue: venue, citations: citations)

        let authors = work.authorships?.compactMap { $0.author?.displayName } ?? []
        let abstract = restoreAbstract(from: work.abstractInvertedIndex)
        let landingPage = work.primaryLocation?.landingPageUrl ?? work.doi ?? work.id
        let pdf = work.primaryLocation?.pdfUrl ?? work.openAccess?.oaUrl

        return Paper(
            id: work.id,
            doi: work.doi,
            title: work.displayName ?? work.title ?? "",
            authors: authors,
            publicationDate: work.publicationDate ?? "",
            publicationYear: work.publicationYear,
            venue: venue,
            venueAbbr: venueAbbr,
            citedByCount: citations,
            abstract: abstract,
            landingPageUrl: landingPage,
            pdfUrl: pdf,
            track: track,
            score: score,
            tier: tier
        )
    }

    private static let displayFields =
        "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access"

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        var userAgent = "FacetX/1.0"
        if !config.openalex.mailto.isEmpty {
            userAgent += " (mailto:\(config.openalex.mailto))"
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decodeWorks(from data: Data) -> [OpenAlexWork] {
        (try? JSONDecoder().decode(OpenAlexResponse.self, from: data))?.results ?? []
    }

    // MARK: - Manual import helpers

    func fetchByDOI(_ doi: String) async -> Paper? {
        let normalised = doi
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "doi.org/", with: "")
        guard !normalised.isEmpty else { return nil }

        var components = URLComponents(string: config.openalex.base_url)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "filter", value: "doi:\(normalised)"),
            URLQueryItem(name: "select", value: Self.displayFields)
        ]
        if !config.openalex.mailto.isEmpty {
            items.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return decodeWorks(from: data).first.map { parseWork($0, track: "") }
        } catch {
            print("OpenAlex fetchByDOI failed: \(error)")
            return nil
        }
    }

    func fetchByTitle(_ title: String, limit: Int = 5) async -> [Paper] {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: config.openalex.base_url)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "search", value: title),
            URLQueryItem(name: "per_page", value: String(min(limit, 25))),
            URLQueryItem(name: "select", value: Self.displayFields)
        ]
        if !config.openalex.mailto.isEmpty {
            items.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
        }
        components?.queryItems = items
        guard let url = components?.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return decodeWorks(from: data).map { parseWork($0, track: "") }
        } catch {
            print("OpenAlex fetchByTitle failed: \(error)")
            return []
        }
    }
}
