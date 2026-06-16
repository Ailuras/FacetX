import Foundation

enum CitationExporter {

    // Strips "https://doi.org/" prefix so the exported DOI is bare.
    static func stripDoiPrefix(_ doi: String) -> String {
        var value = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://doi.org/", "http://doi.org/", "doi.org/"] {
            if value.lowercased().hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        return value
    }

    static func citeKey(for paper: Paper) -> String {
        let surname = paper.authors.first.flatMap { surnameToken(from: $0) } ?? "anon"
        let year = paper.publicationYear.map(String.init) ?? ""
        let titleWord = firstWord(of: paper.title)
        let key = surname + year + titleWord
        let cleaned = asciiAlnum(key)
        return cleaned.isEmpty ? "ref" : cleaned
    }

    static func bibtex(for paper: Paper) -> String {
        var fields: [(String, String)] = []

        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            fields.append(("title", "{\(escapeBibtex(title))}"))
        }
        if !paper.authors.isEmpty {
            let authors = paper.authors
                .map { escapeBibtex($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .joined(separator: " and ")
            fields.append(("author", authors))
        }
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            fields.append(("journal", escapeBibtex(venue)))
        }
        if let year = paper.publicationYear {
            fields.append(("year", String(year)))
        }
        if let doi = bareDoi(paper.doi) {
            fields.append(("doi", escapeBibtex(doi)))
        }
        let landing = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !landing.isEmpty {
            fields.append(("url", escapeBibtex(landing)))
        }

        let body = fields
            .map { "  \($0.0) = {\($0.1)}" }
            .joined(separator: ",\n")

        return "@article{\(citeKey(for: paper)),\n\(body)\n}"
    }

    static func bibtex(for papers: [Paper]) -> String {
        papers.map { bibtex(for: $0) }.joined(separator: "\n\n")
    }

    static func apa(for paper: Paper) -> String {
        var parts: [String] = []

        if let authorList = apaAuthorList(paper.authors) {
            parts.append(authorList)
        }
        if let year = paper.publicationYear {
            parts.append("(\(year)).")
        } else {
            parts.append("(n.d.).")
        }

        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            parts.append(title.hasSuffix(".") ? title : "\(title).")
        }

        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            parts.append("\(venue).")
        }

        if let url = canonicalUrl(for: paper) {
            parts.append(url)
        }

        return parts.joined(separator: " ")
    }

    static func apa(for papers: [Paper]) -> String {
        papers.map { apa(for: $0) }.joined(separator: "\n\n")
    }

    static func markdown(for paper: Paper) -> String {
        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePart: String
        if title.isEmpty {
            titlePart = ""
        } else if let url = canonicalUrl(for: paper) {
            titlePart = "[\(escapeMarkdown(title))](\(url))"
        } else {
            titlePart = escapeMarkdown(title)
        }

        var trailing: [String] = []
        if !paper.authors.isEmpty {
            trailing.append(escapeMarkdown(paper.authors.joined(separator: ", ")))
        }
        if let year = paper.publicationYear {
            trailing.append("(\(year))")
        }
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            trailing.append("*\(escapeMarkdown(venue))*")
        }

        let suffix = trailing.joined(separator: " ")
        if titlePart.isEmpty { return suffix }
        if suffix.isEmpty   { return titlePart }
        return "\(titlePart) — \(suffix)"
    }

    static func markdown(for papers: [Paper]) -> String {
        papers.map { "- \(markdown(for: $0))" }.joined(separator: "\n")
    }

    static func ris(for paper: Paper) -> String {
        var lines: [String] = ["TY  - JOUR"]

        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            lines.append("TI  - \(title)")
        }
        for author in paper.authors {
            let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append("AU  - \(trimmed)")
        }
        if let year = paper.publicationYear {
            lines.append("PY  - \(year)")
        }
        let dateField = paper.publicationDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dateField.isEmpty {
            lines.append("DA  - \(dateField.replacingOccurrences(of: "-", with: "/"))")
        }
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            lines.append("JO  - \(venue)")
        }
        let abstract = paper.abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        if !abstract.isEmpty {
            lines.append("AB  - \(abstract)")
        }
        if let doi = bareDoi(paper.doi) {
            lines.append("DO  - \(doi)")
        }
        let landing = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !landing.isEmpty {
            lines.append("UR  - \(landing)")
        }

        lines.append("ER  - ")
        return lines.joined(separator: "\n")
    }

    static func ris(for papers: [Paper]) -> String {
        papers.map { ris(for: $0) }.joined(separator: "\n\n")
    }

    static func plain(for paper: Paper) -> String {
        var parts: [String] = []

        if !paper.authors.isEmpty {
            parts.append(paper.authors.joined(separator: ", "))
        }
        if let year = paper.publicationYear {
            parts.append("(\(year))")
        }
        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            parts.append("\"\(title)\"")
        }
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            parts.append(venue)
        }
        if let url = canonicalUrl(for: paper) {
            parts.append(url)
        }
        return parts.joined(separator: ". ")
    }

    static func plain(for papers: [Paper]) -> String {
        papers.map { plain(for: $0) }.joined(separator: "\n")
    }

    static func csv(for papers: [Paper]) -> String {
        let header = ["Title", "Authors", "Year", "Venue", "DOI",
                      "Citations", "Score", "Tier", "Status", "URL"]
        var rows: [String] = [header.joined(separator: ",")]

        for paper in papers {
            let row: [String] = [
                paper.title,
                paper.authors.joined(separator: "; "),
                paper.publicationYear.map(String.init) ?? "",
                paper.venue,
                bareDoi(paper.doi) ?? "",
                String(paper.citedByCount),
                String(format: "%.2f", paper.score),
                String(paper.tier),
                paper.status.rawValue,
                canonicalUrl(for: paper) ?? ""
            ]
            rows.append(row.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func escapeBibtex(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "{", "}", "&", "%", "$", "#", "_":
                out.append("\\"); out.append(ch)
            case "~":
                out.append("\\textasciitilde{}")
            case "^":
                out.append("\\textasciicircum{}")
            case "\\":
                out.append("\\textbackslash{}")
            default:
                out.append(ch)
            }
        }
        return out
    }

    private static func bareDoi(_ doi: String?) -> String? {
        guard let doi = doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty else {
            return nil
        }
        return stripDoiPrefix(doi)
    }

    private static func surnameToken(from author: String) -> String? {
        let parts = author
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard !parts.isEmpty else { return nil }

        for token in parts.reversed() {
            if !isAuthorSuffix(token) { return token }
        }
        return parts.last
    }

    private static let authorSuffixes: Set<String> = [
        "jr", "sr", "ii", "iii", "iv", "v", "phd", "md", "esq", "esquire", "mba", "dr"
    ]

    private static func isAuthorSuffix(_ token: String) -> Bool {
        let normalized = token
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        return authorSuffixes.contains(normalized)
    }

    private static func firstWord(of title: String) -> String {
        for token in title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            return String(token)
        }
        return ""
    }

    private static func apaAuthorList(_ authors: [String]) -> String? {
        let formatted = authors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(apaAuthor(from:))
        guard !formatted.isEmpty else { return nil }

        let trailing: String
        if formatted.count == 1 {
            trailing = formatted[0]
        } else if formatted.count <= 20 {
            let head = formatted.dropLast().joined(separator: ", ")
            trailing = "\(head), & \(formatted.last!)"
        } else {
            let head = formatted.prefix(19).joined(separator: ", ")
            trailing = "\(head), … \(formatted.last!)"
        }
        return trailing.hasSuffix(".") ? trailing : "\(trailing)."
    }

    private static func apaAuthor(from author: String) -> String {
        let tokens = author
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard tokens.count > 1, let surname = tokens.last else { return author }
        let initials = tokens.dropLast().compactMap { token -> String? in
            guard let first = token.first else { return nil }
            if token.contains("-") {
                let pieces = token.split(separator: "-").compactMap { $0.first }
                let joined = pieces.map { "\($0)." }.joined(separator: "-")
                return joined.isEmpty ? nil : joined
            }
            return "\(first)."
        }
        let initialPart = initials.joined(separator: " ")
        return initialPart.isEmpty ? surname : "\(surname), \(initialPart)"
    }

    private static func canonicalUrl(for paper: Paper) -> String? {
        if let doi = bareDoi(paper.doi) { return "https://doi.org/\(doi)" }
        let landing = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return landing.isEmpty ? nil : landing
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private static func escapeMarkdown(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", "!", "|":
                out.append("\\"); out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    private static func asciiAlnum(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")
        }.map(Character.init))
    }
}
