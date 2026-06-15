import Foundation
import PDFKit

/// Utility class for extracting academic paper metadata from PDF files using pure-local heuristics and system PDFKit APIs.
struct PdfMetadataExtractor {
    
    struct ExtractedData {
        var doi: String?
        var title: String?
        var authors: [String] = []
        var abstract: String?
        var year: Int?
    }
    
    /// Extract metadata from PDF data in memory.
    static func extract(from pdfData: Data) -> ExtractedData {
        guard let document = PDFDocument(data: pdfData) else { return ExtractedData() }
        var data = ExtractedData()
        
        // 1. Extract plain text from the first 3 pages
        var pageTexts: [String] = []
        for i in 0..<min(document.pageCount, 3) {
            if let pageText = document.page(at: i)?.string {
                pageTexts.append(pageText)
            }
        }
        let fullText = pageTexts.joined(separator: "\n")
        
        // 2. Identify DOI or arXiv ID
        if let doi = matchDOI(in: fullText) {
            data.doi = doi
        } else if let arxivId = matchArXiv(in: fullText) {
            // Map arXiv:YYMM.NNNNN to arXiv DOI prefix: 10.48550/arXiv.YYMM.NNNNN
            data.doi = "10.48550/arXiv.\(arxivId)"
        }
        
        // 3. Extract Title (Check attributes first, fallback to heuristics)
        if let attrTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            let cleaned = cleanString(attrTitle)
            if isValidTitle(cleaned) {
                data.title = cleaned
            }
        }
        if data.title == nil, let firstPage = document.page(at: 0) {
            data.title = extractTitle(from: firstPage)
        }
        
        // 4. Extract Abstract
        data.abstract = extractAbstract(from: fullText)
        
        // 5. Extract Authors (Check attributes first, fallback to text heuristics)
        if let attrAuthors = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String {
            let cleaned = cleanString(attrAuthors)
            if isValidAuthorString(cleaned) {
                let parsed = parseAuthorList(cleaned)
                if !parsed.isEmpty {
                    data.authors = parsed
                }
            }
        }
        if data.authors.isEmpty, let title = data.title, let firstPage = document.page(at: 0), let pageText = firstPage.string {
            data.authors = extractAuthors(pageText: pageText, title: title, abstractText: fullText)
        }
        
        // 6. Extract Year (Check text heuristics first, fallback to attributes)
        if let textYear = extractYear(from: fullText) {
            data.year = textYear
        } else if let attrYear = extractYearFromAttributes(in: document) {
            data.year = attrYear
        }
        
        return data
    }
    
    // MARK: - RegEx Identifier Extraction
    
    /// Finds standard DOI format (10.xxxx/xxxx) and cleans common suffixes.
    static func matchDOI(in text: String) -> String? {
        let pattern = #"\b10\.\d{4,9}/[a-zA-Z0-9\-\.\_\;\(\)\/\:\+\=\<\>\~\@\?\&\%]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        var matched = String(text[Range(match.range, in: text)!])
        
        // Clean trailing punctuation
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:)]}> ")
        while let last = matched.last, String(last).rangeOfCharacter(from: trailingPunctuation) != nil {
            matched.removeLast()
        }
        
        return matched.isEmpty ? nil : matched
    }
    
    /// Finds arXiv identifiers (e.g. arXiv:1706.03762 or YYMM.NNNNN).
    static func matchArXiv(in text: String) -> String? {
        // Clean and validate helper
        func cleanAndValidate(_ rawId: String) -> String? {
            var id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            if let vRange = id.range(of: "v\\d+$", options: .regularExpression) {
                id.removeSubrange(vRange)
            }
            guard id.count >= 4 else { return nil }
            let year = Int(id.prefix(2)) ?? 0
            let month = Int(id.dropFirst(2).prefix(2)) ?? 0
            if (year >= 91 || year <= 29) && (month >= 1 && month <= 12) {
                return id
            }
            return nil
        }
        
        // Pattern 1: explicitly starting with arXiv:YYMM.NNNNN
        let explicitPattern = #"(?i)\barXiv:\s*(\d{4}\.\d{4,5}(v\d+)?)\b"#
        if let regex = try? NSRegularExpression(pattern: explicitPattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            let nsMatched = text as NSString
            let range = match.range(at: 1)
            if range.location != NSNotFound {
                let candidate = nsMatched.substring(with: range)
                if let validated = cleanAndValidate(candidate) {
                    return validated
                }
            }
        }
        
        // Pattern 2: bare arXiv ID in format YYMM.NNNN(N)
        let barePattern = #"\b(\d{4}\.\d{4,5})\b"#
        if let regex = try? NSRegularExpression(pattern: barePattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let candidate = (text as NSString).substring(with: range)
                    if let validated = cleanAndValidate(candidate) {
                        return validated
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Title Heuristics
    
    /// Finds the largest font blocks in the first page to reconstruct the title.
    static func extractTitle(from page: PDFPage) -> String? {
        guard let attrString = page.attributedString else {
            return fallbackTitle(from: page.string)
        }
        
        struct TextBlock {
            let text: String
            let size: CGFloat
        }
        
        var blocks: [TextBlock] = []
        
        attrString.enumerateAttribute(.font, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, _ in
            let text = attrString.attributedSubstring(from: range).string
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            var fontSize: CGFloat = 10
            if let font = value as? NSFont {
                fontSize = font.pointSize
            }
            blocks.append(TextBlock(text: text, size: fontSize))
        }
        
        // Filter out blocks likely to be header markers (e.g. page numbers, small margins)
        // Title font size in academic papers is almost always >= 13pt
        let titleCandidates = blocks.filter { $0.size >= 13.0 }
        
        if !titleCandidates.isEmpty {
            // Find the maximum font size among candidates
            let maxSize = titleCandidates.map(\.size).max() ?? 13.0
            
            // Collect all continuous chunks of this max size
            // Note: sometimes there are minor font size variations or tiny non-max characters (like superscript footnote indicators)
            // inside a title. We'll grab any candidate that is within 1pt of the max size.
            let titleChunks = titleCandidates.filter { abs($0.size - maxSize) <= 1.0 }
            
            let combined = titleChunks.map(\.text).joined(separator: "")
            let cleaned = cleanString(combined)
            if cleaned.count >= 5 {
                return cleaned
            }
        }
        
        return fallbackTitle(from: page.string)
    }
    
    private static func fallbackTitle(from pageText: String?) -> String? {
        guard let text = pageText else { return nil }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Skip first 1-2 short header lines if they look like journal headers (e.g. "Preprint", "arXiv:...")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.lowercased().contains("journal") ||
                line.lowercased().contains("arxiv") ||
                line.lowercased().contains("preprint") ||
                line.count < 6 {
                index += 1
            } else {
                break
            }
        }
        
        if index < lines.count {
            // Join first two meaningful lines as fallback title
            var candidate = lines[index]
            if index + 1 < lines.count && lines[index+1].count > 10 && !lines[index+1].contains("@") {
                candidate += " " + lines[index+1]
            }
            return cleanString(candidate)
        }
        return nil
    }
    
    // MARK: - Abstract Heuristics
    
    static func extractAbstract(from text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        
        // Find abstract boundary keywords
        let abstractKeywords = ["abstract", "a b s t r a c t", "摘要"]
        var abstractStartIndex: String.Index?
        
        for keyword in abstractKeywords {
            if let range = normalized.range(of: keyword, options: [.caseInsensitive]) {
                abstractStartIndex = range.upperBound
                break
            }
        }
        
        guard let startIdx = abstractStartIndex else { return nil }
        
        var abstractContent = String(normalized[startIdx...])
        
        // Clean leading symbols (e.g. ".", ":", "—", spaces, linebreaks)
        let leadingExclusions = CharacterSet(charactersIn: ".:—-\r\n\t ")
        while let first = abstractContent.first, String(first).rangeOfCharacter(from: leadingExclusions) != nil {
            abstractContent.removeFirst()
        }
        
        // Locate end boundary of the abstract (typically the start of "1 Introduction" or similar sections)
        let introKeywords = [
            "\n1 introduction", "\n1. introduction", "\ni. introduction",
            "\n1.  introduction", "\nintroduction", "\n1  introduction",
            "\n1. background", "\n1 background", "\nbackground"
        ]
        
        var abstractEndIndex = abstractContent.endIndex
        
        for keyword in introKeywords {
            if let range = abstractContent.range(of: keyword, options: [.caseInsensitive]) {
                if range.lowerBound < abstractEndIndex {
                    abstractEndIndex = range.lowerBound
                }
            }
        }
        
        // If we found a boundary, slice it. Otherwise clamp it to a maximum of 1800 characters to avoid grabbing the whole paper
        let sliced = String(abstractContent[..<abstractEndIndex])
        let cleaned = cleanString(sliced)
        
        if cleaned.count > 1800 {
            return String(cleaned.prefix(1500)) + "..."
        }
        return cleaned.isEmpty ? nil : cleaned
    }
    
    // MARK: - Authors Heuristics
    
    static func extractAuthors(pageText: String, title: String, abstractText: String) -> [String] {
        let normalizedPage = pageText.replacingOccurrences(of: "\r", with: "\n")
        
        var textAfterTitle = normalizedPage
        
        // Try to locate the title in the page text and slice after it
        let titleCleaned = title.lowercased().replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if !titleCleaned.isEmpty {
            let titleWords = title.components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            if titleWords.count >= 2 {
                if let firstWord = titleWords.first,
                   let firstWordRange = normalizedPage.range(of: firstWord, options: [.caseInsensitive]) {
                    let searchRange = firstWordRange.upperBound..<normalizedPage.endIndex
                    let maxSearchEnd = normalizedPage.index(searchRange.lowerBound, offsetBy: min(1000, normalizedPage.distance(from: searchRange.lowerBound, to: searchRange.upperBound)), limitedBy: normalizedPage.endIndex) ?? searchRange.upperBound
                    
                    if let lastWord = titleWords.last,
                       let lastWordRange = normalizedPage.range(of: lastWord, options: [.backwards, .caseInsensitive], range: firstWordRange.upperBound..<maxSearchEnd) {
                        textAfterTitle = String(normalizedPage[lastWordRange.upperBound...])
                    }
                }
            }
        }
        
        // Find Abstract boundary in the sliced text
        let abstractKeywords = ["abstract", "摘要", "a b s t r a c t"]
        var abstractIndex: String.Index?
        for kw in abstractKeywords {
            if let range = textAfterTitle.range(of: kw, options: [.caseInsensitive]) {
                abstractIndex = range.lowerBound
                break
            }
        }
        
        let candidateText: String
        if let idx = abstractIndex {
            candidateText = String(textAfterTitle[..<idx])
        } else {
            let lines = textAfterTitle.components(separatedBy: .newlines)
            candidateText = lines.prefix(8).joined(separator: "\n")
        }
        
        let lines = candidateText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        var authorLines: [String] = []
        
        let exclusions = [
            "university", "institute", "dept", "department", "school", "laboratory",
            "lab", "center", "centre", "corporation", "inc.", "co.", "ltd", "email",
            "@", "abstract", "http", "www", "research", "technology", "sciences",
            "china", "usa", "state", "national", "association", "society",
            "college", "academy", "group", "division", "faculty", "google", "microsoft",
            "meta", "openai", "deepmind", "apple", "ibm", "amazon", "intel", "yahoo",
            "california", "new york", "massachusetts", "london", "beijing", "toronto",
            "cambridge", "oxford", "zurich", "tokyo", "paris", "berlin", "munich",
            "vancouver", "seattle", "boston", "silicon", "zip", "postal", "road",
            "street", "avenue", "building", "floor", "suite", "plaza", "drive",
            "germany", "france", "united kingdom", "canada", "australia", "switzerland",
            "japan", "india", "korea", "singapore", "netherlands", "sweden", "italy",
            "spain", "brazil", "russia", "belgium", "austria", "denmark", "norway",
            "january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december", "preprint", "under review",
            "corresponding", "contribution", "contributed", "equal"
        ]
        
        let titleLower = title.lowercased().replacingOccurrences(of: " ", with: "")
        
        for line in lines {
            let lineLower = line.lowercased()
            let lineNoSpace = lineLower.replacingOccurrences(of: " ", with: "")
            
            // Skip title lines
            if titleLower.contains(lineNoSpace) || lineNoSpace.contains(titleLower) && lineNoSpace.count > 4 {
                continue
            }
            
            // Skip institutional or other excluded keywords
            var isExcluded = false
            for exclusion in exclusions {
                if lineLower.contains(exclusion) {
                    isExcluded = true
                    break
                }
            }
            if isExcluded { continue }
            
            // Skip lines with too many digits (e.g. zip codes, years, page numbers)
            let digits = line.filter { $0.isNumber }.count
            if digits > 4 {
                continue
            }
            
            // Ensure the line actually has some alphabetic characters
            let letters = line.filter { $0.isLetter }.count
            if letters < 3 {
                continue
            }
            
            // If letters are less than 40% of the line, it's probably institutional noise or math
            if Double(letters) / Double(line.count) < 0.4 {
                continue
            }
            
            authorLines.append(line)
        }
        
        // We take the first 1-2 lines as author lines
        guard !authorLines.isEmpty else { return [] }
        
        // Join them and split by separators
        var combinedAuthorLine = authorLines[0]
        if authorLines.count > 1 && authorLines[0].count < 30 && !authorLines[1].contains(",") {
            combinedAuthorLine += ", " + authorLines[1]
        }
        
        return parseAuthorList(combinedAuthorLine)
    }
    
    // MARK: - Year Heuristics
    
    static func extractYear(from text: String) -> Int? {
        // 1. Try finding context-rich years (e.g., Copyright 2020, Published 2021, Accepted 2019, © 2018)
        let contextPattern = #"(?i)(?:copyright|published|accepted|received|proceedings|©)\s*(?:in|on|at)?\s*\b(19\d{2}|20[0-2]\d)\b"#
        if let regex = try? NSRegularExpression(pattern: contextPattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            let nsMatched = text as NSString
            let range = match.range(at: 1)
            if range.location != NSNotFound, let val = Int(nsMatched.substring(with: range)) {
                return val
            }
        }
        
        // 2. Try finding years in parentheses/brackets, e.g. "(2020)" or "[2020]"
        let parenPattern = #"[\(\[](19\d{2}|20[0-3]\d)[\)\]]"#
        if let parenRegex = try? NSRegularExpression(pattern: parenPattern, options: []) {
            let matches = parenRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let yearStr = (text as NSString).substring(with: range)
                    if let val = Int(yearStr), val >= 1980 && val <= 2030 {
                        return val
                    }
                }
            }
        }
        
        // 3. Fallback to any 4-digit number between 1980 and 2030
        let pattern = #"\b(19\d{2}|20[0-3]\d)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let range = match.range(at: 0)
                if range.location != NSNotFound {
                    let candidateStr = (text as NSString).substring(with: range)
                    if let val = Int(candidateStr), val >= 1980 && val <= 2030 {
                        return val
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Document Attribute Extractions & Validations
    
    static func extractYearFromAttributes(in document: PDFDocument) -> Int? {
        if let creationDate = document.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date {
            let year = Calendar.current.component(.year, from: creationDate)
            if year >= 1980 && year <= 2030 {
                return year
            }
        }
        if let modDate = document.documentAttributes?[PDFDocumentAttribute.modificationDateAttribute] as? Date {
            let year = Calendar.current.component(.year, from: modDate)
            if year >= 1980 && year <= 2030 {
                return year
            }
        }
        for key in [PDFDocumentAttribute.creationDateAttribute, PDFDocumentAttribute.modificationDateAttribute] {
            if let dateStr = document.documentAttributes?[key] as? String {
                let pattern = #"\b(19\d{2}|20[0-3]\d)\b"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: dateStr, options: [], range: NSRange(dateStr.startIndex..., in: dateStr)) {
                    let nsStr = dateStr as NSString
                    if let val = Int(nsStr.substring(with: match.range)) {
                        return val
                    }
                }
            }
        }
        return nil
    }
    
    static func isValidTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        guard t.count >= 8 else { return false }
        guard t.contains(" ") else { return false }
        
        let invalidKeywords = [
            ".pdf", ".docx", ".doc", "untitled", "template", "microsoft word",
            "latex", "layout", "class file", "instructions for", "manuscript",
            "author guidelines", "proceeding", "journal article", "formatting",
            "paper format", "acm format", "ieee format", "springer format"
        ]
        for keyword in invalidKeywords {
            if t.contains(keyword) {
                return false
            }
        }
        return true
    }
    
    static func isValidAuthorString(_ author: String) -> Bool {
        let a = author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.count >= 3 else { return false }
        
        let invalidKeywords = [
            "adobe", "distiller", "latex", "dvips", "author", "user", "admin",
            "administrator", "desktop", "unknown", "publisher", "microsoft",
            "word", "writer", "creator", "page", "frame", "canvas", "staff",
            "placeholder", "none", "n/a", "no author", "created by", "modified by"
        ]
        for keyword in invalidKeywords {
            if a.contains(keyword) {
                return false
            }
        }
        if a.contains("@") || a.contains("http") || a.contains("www") { return false }
        
        let letters = a.filter { $0.isLetter }.count
        guard letters >= 3 else { return false }
        
        return true
    }
    
    static func parseAuthorList(_ authorStr: String) -> [String] {
        let separators = [" and ", " & ", ",", ";", "\n", "\r"]
        var parsed: [String] = [authorStr]
        for sep in separators {
            var temp: [String] = []
            for item in parsed {
                let parts = item.components(separatedBy: sep)
                temp.append(contentsOf: parts)
            }
            parsed = temp
        }
        return parsed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && !isGenericName($0) }
            .map { cleanAuthorName($0) }
    }
    
    static func isGenericName(_ name: String) -> Bool {
        let n = name.lowercased()
        let generics = ["and", "or", "author", "unknown", "et al", "et al.", "others"]
        return generics.contains(n)
    }
    
    static func cleanAuthorName(_ name: String) -> String {
        var cleaned = name
        let parenPattern = #"\s*[\[(][0-9a-zA-Z,*†‡§#\s-]+[\])]"#
        cleaned = cleaned.replacingOccurrences(of: parenPattern, with: "", options: .regularExpression)
        
        let charPattern = #"[0-9*†‡§#]"#
        cleaned = cleaned.replacingOccurrences(of: charPattern, with: "", options: .regularExpression)
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        let formattedWords = words.map { word -> String in
            let isAllLower = word == word.lowercased()
            let isAllUpper = word == word.uppercased()
            if isAllLower || isAllUpper {
                return word.capitalized
            }
            return word
        }
        
        return formattedWords.joined(separator: " ")
    }
    
    // MARK: - Helper Cleaners
    
    private static func cleanString(_ input: String) -> String {
        let spaced = input.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return spaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
