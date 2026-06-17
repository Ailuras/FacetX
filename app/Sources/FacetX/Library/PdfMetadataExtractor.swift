import Foundation
import PDFKit

struct PdfMetadataExtractor {
    struct ExtractedData {
        var doi: String?
        var title: String?
        var authors: [String] = []
        var abstract: String?
        var year: Int?
    }

    static func extract(from pdfData: Data) -> ExtractedData {
        guard let document = PDFDocument(data: pdfData) else { return ExtractedData() }
        var data = ExtractedData()

        let pageTexts = (0..<min(document.pageCount, 3)).compactMap {
            document.page(at: $0)?.string
        }
        let fullText = pageTexts.joined(separator: "\n")

        if let doi = matchDOI(in: fullText) {
            data.doi = doi
        } else if let arxiv = matchArXiv(in: fullText) {
            data.doi = "10.48550/arXiv.\(arxiv)"
        }

        if let attrTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            let cleaned = cleanString(attrTitle)
            if isValidTitle(cleaned) { data.title = cleaned }
        }
        if data.title == nil {
            data.title = extractTitle(from: document.page(at: 0)?.string)
        }

        data.abstract = extractAbstract(from: fullText)

        if let attrAuthors = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String {
            let parsed = parseAuthorList(cleanString(attrAuthors))
            if !parsed.isEmpty { data.authors = parsed }
        }
        if data.authors.isEmpty, let title = data.title, let firstPage = document.page(at: 0)?.string {
            data.authors = extractAuthors(pageText: firstPage, title: title)
        }

        data.year = extractYear(from: fullText)
        return data
    }

    static func matchDOI(in text: String) -> String? {
        let pattern = #"\b10\.\d{4,9}/[a-zA-Z0-9\-\.\_\;\(\)\/\:\+\=\<\>\~\@\?\&\%]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        var matched = String(text[range])
        while let last = matched.last, ".,;:)]}> ".contains(last) {
            matched.removeLast()
        }
        return matched.isEmpty ? nil : matched
    }

    static func matchArXiv(in text: String) -> String? {
        let pattern = #"(?i)\barXiv:\s*(\d{4}\.\d{4,5}(v\d+)?)\b|\b(\d{4}\.\d{4,5})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { continue }
            var id = String(text[swiftRange])
            if let version = id.range(of: "v\\d+$", options: .regularExpression) {
                id.removeSubrange(version)
            }
            let month = Int(id.dropFirst(2).prefix(2)) ?? 0
            if (1...12).contains(month) { return id }
        }
        return nil
    }

    private static func extractTitle(from pageText: String?) -> String? {
        guard let pageText else { return nil }
        let lines = pageText.components(separatedBy: .newlines)
            .map { cleanString($0) }
            .filter { !$0.isEmpty }
        for index in lines.indices {
            let line = lines[index]
            let lower = line.lowercased()
            if lower.contains("journal") || lower.contains("arxiv") || lower.contains("preprint") || line.count < 6 {
                continue
            }
            var title = line
            if index + 1 < lines.count, lines[index + 1].count > 10, !lines[index + 1].contains("@") {
                title += " " + lines[index + 1]
            }
            return isValidTitle(title) ? title : nil
        }
        return nil
    }

    private static func extractAbstract(from text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        guard let start = normalized.range(of: #"(?i)\babstract\b|a b s t r a c t|摘要"#, options: .regularExpression) else {
            return nil
        }
        var content = String(normalized[start.upperBound...])
        content = content.trimmingCharacters(in: CharacterSet(charactersIn: ".:—-\n\t "))

        let endPatterns = [
            #"(?i)\n\s*1\.?\s+introduction\b"#,
            #"(?i)\n\s*introduction\b"#,
            #"(?i)\n\s*keywords?\b"#,
            #"(?i)\n\s*background\b"#
        ]
        var endIndex = content.endIndex
        for pattern in endPatterns {
            if let range = content.range(of: pattern, options: .regularExpression), range.lowerBound < endIndex {
                endIndex = range.lowerBound
            }
        }
        let abstract = cleanString(String(content[..<endIndex]))
        return abstract.count >= 40 ? abstract : nil
    }

    private static func extractAuthors(pageText: String, title: String) -> [String] {
        let lines = pageText.components(separatedBy: .newlines)
            .map { cleanString($0) }
            .filter { !$0.isEmpty }
        guard let titleIndex = lines.firstIndex(where: {
            isSimilar($0, title) || isSimilar(title, $0)
        }) else { return [] }

        let candidates = lines.dropFirst(titleIndex + 1).prefix(4)
        let authorLine = candidates.first {
            !$0.contains("@") &&
            !$0.lowercased().contains("abstract") &&
            $0.split(separator: " ").count <= 16
        }
        return authorLine.map(parseAuthorList) ?? []
    }

    private static func parseAuthorList(_ raw: String) -> [String] {
        raw.replacingOccurrences(of: #"[\d\*\†\‡\§]+"#, with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { cleanString($0) }
            .filter { $0.count >= 2 && !$0.contains("@") }
    }

    private static func extractYear(from text: String) -> Int? {
        let pattern = #"\b(19|20)\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Int(text[range])
    }

    private static func cleanString(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidTitle(_ value: String) -> Bool {
        value.count >= 8 && !value.contains("@") && !value.lowercased().hasPrefix("abstract")
    }

    private static func isSimilar(_ a: String, _ b: String) -> Bool {
        let cleanA = a.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let cleanB = b.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        guard !cleanA.isEmpty, !cleanB.isEmpty else { return false }
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA)
    }
}
