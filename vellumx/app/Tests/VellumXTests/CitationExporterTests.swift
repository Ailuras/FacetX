import XCTest
@testable import VellumX

final class CitationExporterTests: XCTestCase {

    private func makePaper(
        title: String = "Attention Is All You Need",
        authors: [String] = ["Ashish Vaswani", "Noam Shazeer"],
        year: Int? = 2017,
        venue: String = "NeurIPS",
        doi: String? = "https://doi.org/10.5555/3295222",
        landing: String = "https://example.org/paper"
    ) -> Paper {
        Paper(
            id: "W1", doi: doi, title: title, authors: authors,
            publicationYear: year, venue: venue, landingPageUrl: landing
        )
    }

    // MARK: - citeKey

    func testCiteKeyNormalCase() {
        XCTAssertEqual(CitationExporter.citeKey(for: makePaper()), "vaswani2017attention")
    }

    func testCiteKeyMissingAuthor() {
        let key = CitationExporter.citeKey(for: makePaper(authors: []))
        XCTAssertEqual(key, "anon2017attention")
    }

    func testCiteKeyMissingYear() {
        let key = CitationExporter.citeKey(for: makePaper(year: nil))
        XCTAssertEqual(key, "vaswaniattention")
    }

    func testCiteKeyStripsPunctuationAndUnicode() {
        let key = CitationExporter.citeKey(
            for: makePaper(title: "Café: Déjà-vu!", authors: ["Émile Zölá"], year: 2020)
        )
        // Non-ASCII letters are stripped; only ascii alnum remains.
        XCTAssertEqual(key, "zl2020caf")
    }

    func testCiteKeySkipsGenerationalSuffix() {
        let key = CitationExporter.citeKey(
            for: makePaper(authors: ["John Smith Jr."], year: 2020)
        )
        XCTAssertEqual(key, "smith2020attention")
    }

    func testCiteKeySkipsRomanNumeralSuffix() {
        let key = CitationExporter.citeKey(
            for: makePaper(authors: ["Henry Ford III"], year: 2020)
        )
        XCTAssertEqual(key, "ford2020attention")
    }

    func testCiteKeySkipsProfessionalSuffix() {
        let key = CitationExporter.citeKey(
            for: makePaper(authors: ["Alice Brown PhD"], year: 2020)
        )
        XCTAssertEqual(key, "brown2020attention")
    }

    func testCiteKeyFallsBackToRefWhenNothingASCII() {
        // Author present but non-ASCII, no year, no ASCII title word → empty → "ref".
        let key = CitationExporter.citeKey(for: makePaper(title: "！？", authors: ["你好"], year: nil))
        XCTAssertEqual(key, "ref")
    }

    // MARK: - BibTeX

    func testBibtexContainsCoreFields() {
        let bib = CitationExporter.bibtex(for: makePaper())
        XCTAssertTrue(bib.hasPrefix("@article{vaswani2017attention,"))
        XCTAssertTrue(bib.contains("author = {Ashish Vaswani and Noam Shazeer}"))
        XCTAssertTrue(bib.contains("journal = {NeurIPS}"))
        XCTAssertTrue(bib.contains("year = {2017}"))
        // DOI is exported bare (prefix stripped).
        XCTAssertTrue(bib.contains("doi = {10.5555/3295222}"))
        XCTAssertTrue(bib.contains("url = {https://example.org/paper}"))
        XCTAssertTrue(bib.hasSuffix("}"))
    }

    func testBibtexEscapesSpecialCharacters() {
        let bib = CitationExporter.bibtex(
            for: makePaper(title: "Cost & Benefit of 50% _gains_ #1", doi: nil)
        )
        XCTAssertTrue(bib.contains("Cost \\& Benefit of 50\\% \\_gains\\_ \\#1"))
    }

    func testBibtexOmitsMissingFields() {
        let bib = CitationExporter.bibtex(
            for: makePaper(authors: [], venue: "", doi: nil, landing: "")
        )
        XCTAssertFalse(bib.contains("author ="))
        XCTAssertFalse(bib.contains("journal ="))
        XCTAssertFalse(bib.contains("doi ="))
        XCTAssertFalse(bib.contains("url ="))
        XCTAssertTrue(bib.contains("title ="))
        XCTAssertTrue(bib.contains("year ="))
    }

    // MARK: - APA

    func testApaTwoAuthors() {
        let s = CitationExporter.apa(for: makePaper())
        XCTAssertEqual(
            s,
            "Vaswani, A., & Shazeer, N. (2017). Attention Is All You Need. NeurIPS. https://doi.org/10.5555/3295222"
        )
    }

    func testApaSingleAuthorFallbackToLandingUrl() {
        let s = CitationExporter.apa(for: makePaper(
            authors: ["Jane Doe"], doi: nil, landing: "https://example.org/paper"
        ))
        XCTAssertEqual(
            s,
            "Doe, J. (2017). Attention Is All You Need. NeurIPS. https://example.org/paper"
        )
    }

    func testApaSingleNameAuthorPreserved() {
        let s = CitationExporter.apa(for: makePaper(authors: ["Plato"]))
        XCTAssertTrue(s.hasPrefix("Plato. (2017)."))
    }

    func testApaNoYearUsesNd() {
        let s = CitationExporter.apa(for: makePaper(year: nil))
        XCTAssertTrue(s.contains("(n.d.)."))
    }

    func testApaCollapsesLongAuthorList() {
        let many = (1...25).map { "Author\($0) Surname\($0)" }
        let s = CitationExporter.apa(for: makePaper(authors: many))
        XCTAssertTrue(s.contains("Surname1, A."))
        XCTAssertTrue(s.contains("Surname19, A."))
        XCTAssertTrue(s.contains("… Surname25, A."))
        XCTAssertFalse(s.contains("Surname20, A."))
    }

    func testApaHyphenatedInitials() {
        let s = CitationExporter.apa(for: makePaper(authors: ["Jean-Luc Picard"]))
        XCTAssertTrue(s.hasPrefix("Picard, J.-L."))
    }

    // MARK: - Markdown

    func testMarkdownIncludesAllFields() {
        let md = CitationExporter.markdown(for: makePaper())
        XCTAssertEqual(
            md,
            "[Attention Is All You Need](https://doi.org/10.5555/3295222) — Ashish Vaswani, Noam Shazeer (2017) *NeurIPS*"
        )
    }

    func testMarkdownPlainTitleWhenNoUrl() {
        let md = CitationExporter.markdown(for: makePaper(doi: nil, landing: ""))
        XCTAssertFalse(md.contains("]("))
        XCTAssertTrue(md.hasPrefix("Attention Is All You Need —"))
    }

    func testMarkdownEscapesSpecialChars() {
        let md = CitationExporter.markdown(
            for: makePaper(title: "C* and _under_ [stuff]", doi: nil, landing: "")
        )
        XCTAssertTrue(md.contains("C\\* and \\_under\\_ \\[stuff\\]"))
    }

    func testMarkdownBulletList() {
        let p1 = makePaper(title: "First")
        let p2 = makePaper(title: "Second")
        let md = CitationExporter.markdown(for: [p1, p2])
        XCTAssertTrue(md.hasPrefix("- "))
        XCTAssertEqual(md.split(separator: "\n").count, 2)
    }

    // MARK: - RIS

    func testRisContainsCoreTags() {
        let ris = CitationExporter.ris(for: makePaper())
        XCTAssertTrue(ris.hasPrefix("TY  - JOUR"))
        XCTAssertTrue(ris.contains("TI  - Attention Is All You Need"))
        XCTAssertTrue(ris.contains("AU  - Ashish Vaswani"))
        XCTAssertTrue(ris.contains("AU  - Noam Shazeer"))
        XCTAssertTrue(ris.contains("PY  - 2017"))
        XCTAssertTrue(ris.contains("JO  - NeurIPS"))
        XCTAssertTrue(ris.contains("DO  - 10.5555/3295222"))
        XCTAssertTrue(ris.hasSuffix("ER  - "))
    }

    func testRisOmitsMissingFields() {
        let ris = CitationExporter.ris(for: makePaper(
            authors: [], year: nil, venue: "", doi: nil, landing: ""
        ))
        XCTAssertFalse(ris.contains("AU  -"))
        XCTAssertFalse(ris.contains("PY  -"))
        XCTAssertFalse(ris.contains("JO  -"))
        XCTAssertFalse(ris.contains("DO  -"))
        XCTAssertFalse(ris.contains("UR  -"))
        XCTAssertTrue(ris.contains("TI  -"))
    }

    func testRisFormatsDateField() {
        var paper = makePaper()
        paper.publicationDate = "2017-06-12"
        let ris = CitationExporter.ris(for: paper)
        XCTAssertTrue(ris.contains("DA  - 2017/06/12"))
    }

    // MARK: - Plain text

    func testPlainContainsAllFields() {
        let s = CitationExporter.plain(for: makePaper())
        XCTAssertEqual(
            s,
            "Ashish Vaswani, Noam Shazeer. (2017). \"Attention Is All You Need\". NeurIPS. https://doi.org/10.5555/3295222"
        )
    }

    func testPlainDropsMissingFieldsCleanly() {
        let s = CitationExporter.plain(for: makePaper(
            authors: [], year: nil, venue: "", doi: nil, landing: ""
        ))
        XCTAssertEqual(s, "\"Attention Is All You Need\"")
    }

    func testPlainMultiplePapersOnePerLine() {
        let s = CitationExporter.plain(for: [makePaper(title: "A"), makePaper(title: "B")])
        XCTAssertEqual(s.split(separator: "\n").count, 2)
    }

    // MARK: - CSV

    func testCsvHeaderAndRow() {
        let csv = CitationExporter.csv(for: [makePaper()])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            String(lines[0]),
            "Title,Authors,Year,Venue,DOI,Citations,Score,Tier,Status,URL"
        )
        // Authors joined with semicolons, score is %.2f, status is rawValue.
        XCTAssertTrue(String(lines[1]).contains("Ashish Vaswani; Noam Shazeer"))
        XCTAssertTrue(String(lines[1]).contains(",2017,"))
        XCTAssertTrue(String(lines[1]).contains(",pending,"))
        XCTAssertTrue(String(lines[1]).hasSuffix("https://doi.org/10.5555/3295222"))
    }

    func testCsvEscapesCommasAndQuotes() {
        let csv = CitationExporter.csv(for: [
            makePaper(title: "Hello, \"World\"", authors: ["Doe, Jane"])
        ])
        let row = String(csv.split(separator: "\n").last!)
        XCTAssertTrue(row.contains("\"Hello, \"\"World\"\"\""))
        XCTAssertTrue(row.contains("\"Doe, Jane\""))
    }

    func testCsvEmptyPapers() {
        let csv = CitationExporter.csv(for: [])
        XCTAssertEqual(csv, "Title,Authors,Year,Venue,DOI,Citations,Score,Tier,Status,URL")
    }

    func testRisMultiplePapersSeparatedByBlankLine() {
        let p1 = makePaper(title: "First")
        let p2 = makePaper(title: "Second")
        let ris = CitationExporter.ris(for: [p1, p2])
        XCTAssertEqual(ris.components(separatedBy: "TY  - JOUR").count - 1, 2)
        XCTAssertTrue(ris.contains("\n\nTY  - JOUR"))
    }
}
