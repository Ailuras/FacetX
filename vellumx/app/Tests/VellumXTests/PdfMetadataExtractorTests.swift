import XCTest
import PDFKit
import CoreGraphics
import CoreText
@testable import VellumX

final class PdfMetadataExtractorTests: XCTestCase {
    
    // MARK: - RegEx Tests
    
    func testMatchDOI() {
        let text1 = "Some text with DOI 10.1038/nature12373 in the middle."
        XCTAssertEqual(PdfMetadataExtractor.matchDOI(in: text1), "10.1038/nature12373")
        
        let text2 = "DOI: 10.1109/CVPR.2016.90. Next sentence."
        XCTAssertEqual(PdfMetadataExtractor.matchDOI(in: text2), "10.1109/CVPR.2016.90")
        
        let text3 = "No DOI here."
        XCTAssertNil(PdfMetadataExtractor.matchDOI(in: text3))
        
        let text4 = "Messy DOI suffix: 10.1002/asi.20116;)"
        XCTAssertEqual(PdfMetadataExtractor.matchDOI(in: text4), "10.1002/asi.20116")
    }
    
    func testMatchArXiv() {
        let text1 = "arXiv:1706.03762v1 [cs.CL] 12 Jun 2017"
        XCTAssertEqual(PdfMetadataExtractor.matchArXiv(in: text1), "1706.03762")
        
        let text2 = "This is paper 2302.10234, an interesting read."
        XCTAssertEqual(PdfMetadataExtractor.matchArXiv(in: text2), "2302.10234")
        
        let text3 = "Not an arxiv: 9999.8888 because the year/month prefix is invalid."
        XCTAssertNil(PdfMetadataExtractor.matchArXiv(in: text3))
    }
    
    // MARK: - Heuristic Fields Extraction Tests
    
    func testExtractAbstract() {
        let text = """
        Attention Is All You Need
        Ashish Vaswani, Noam Shazeer...
        
        Abstract
        We propose a new simple network architecture, the Transformer, based solely on attention mechanisms.
        We show that it is superior in quality.
        
        1 Introduction
        The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.
        """
        
        let abstract = PdfMetadataExtractor.extractAbstract(from: text)
        XCTAssertNotNil(abstract)
        XCTAssertTrue(abstract!.contains("We propose a new simple network architecture"))
        XCTAssertFalse(abstract!.contains("1 Introduction"))
    }
    
    func testExtractYear() {
        let text = "Proceedings of the 2017 Conference on Neural Information Processing Systems (NIPS 2017)."
        XCTAssertEqual(PdfMetadataExtractor.extractYear(from: text), 2017)
        
        let textNoParen = "Published in 2021 by MIT Press."
        XCTAssertEqual(PdfMetadataExtractor.extractYear(from: textNoParen), 2021)
    }
    
    func testExtractAuthors() {
        let title = "Attention Is All You Need"
        let pageText = """
        Attention Is All You Need
        Ashish Vaswani, Noam Shazeer, Niki Parmar, Jakob Uszkoreit
        Google Brain
        {avaswani, noam}@google.com
        
        Abstract
        The dominant sequence transduction models...
        """
        
        let authors = PdfMetadataExtractor.extractAuthors(pageText: pageText, title: title, abstractText: pageText)
        XCTAssertEqual(authors.count, 4)
        XCTAssertTrue(authors.contains("Ashish Vaswani"))
        XCTAssertTrue(authors.contains("Noam Shazeer"))
        XCTAssertTrue(authors.contains("Niki Parmar"))
        XCTAssertTrue(authors.contains("Jakob Uszkoreit"))
    }
    
    // MARK: - Full PDF Integration Test
    
    func testFullPDFExtraction() {
        // Generate a simple PDF in memory
        let pdfData = createMockPDFData()
        XCTAssertFalse(pdfData.isEmpty)
        
        // Extract metadata using our extractor
        let extracted = PdfMetadataExtractor.extract(from: pdfData)
        
        XCTAssertEqual(extracted.doi, "10.48550/arXiv.1706.03762")
        XCTAssertEqual(extracted.title, "Attention Is All You Need")
        XCTAssertEqual(extracted.year, 2017)
        XCTAssertNotNil(extracted.abstract)
        XCTAssertTrue(extracted.abstract!.contains("We propose a new simple network architecture"))
        XCTAssertEqual(extracted.authors.count, 2)
        XCTAssertTrue(extracted.authors.contains("Ashish Vaswani"))
        XCTAssertTrue(extracted.authors.contains("Noam Shazeer"))
    }
    
    // MARK: - OpenAlex Live Fetcher Test
    
    @MainActor
    func testOpenAlexFetcherWithRealDOI() async {
        let fetcher = OpenAlexFetcher(
            config: ConfigManager.shared.effectiveConfig,
            venues: []
        )
        let paper = await fetcher.fetchByDOI("10.1038/nature12373")
        XCTAssertNotNil(paper)
        if let paper = paper {
            XCTAssertFalse(paper.title.isEmpty)
            XCTAssertTrue(paper.title.lowercased().contains("thermometry") || paper.title.lowercased().contains("living"))
            XCTAssertFalse(paper.authors.isEmpty)
            XCTAssertEqual(paper.publicationYear, 2013)
        }
    }
    
    // MARK: - Helper to Generate PDF
    
    private func createMockPDFData() -> Data {
        let pdfData = NSMutableData()
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2017, month: 6, day: 12)
        let mockDate = calendar.date(from: components) ?? Date()
        
        let titleKey = "Title" as CFString
        let authorKey = "Author" as CFString
        let dateKey = "CreationDate" as CFString
        
        let info: [CFString: Any] = [
            titleKey: "Attention Is All You Need" as CFString,
            authorKey: "Ashish Vaswani, Noam Shazeer" as CFString,
            dateKey: mockDate as CFDate
        ]
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, info as CFDictionary) else {
            return Data()
        }
        
        context.beginPage(mediaBox: nil)
        
        // Let's create an attributed string to simulate layout styles (large title)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        
        let text = NSMutableAttributedString()
        
        // Add Title (Large Font Size)
        text.append(NSAttributedString(string: "Attention Is All You Need\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .paragraphStyle: paragraph
        ]))
        
        // Add Authors (Medium Font Size)
        text.append(NSAttributedString(string: "Ashish Vaswani, Noam Shazeer\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraph
        ]))
        
        // Add Affiliation (Medium Font Size, should be ignored by heuristics)
        text.append(NSAttributedString(string: "Google Brain\n{avaswani}@google.com\narXiv:1706.03762v1 (2017)\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .paragraphStyle: paragraph
        ]))
        
        // Add Abstract Section
        let alignLeft = NSMutableParagraphStyle()
        alignLeft.alignment = .left
        text.append(NSAttributedString(string: "Abstract\nWe propose a new simple network architecture, the Transformer, based solely on attention mechanisms.\n\n1 Introduction\nMany sequence transduction models...", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .paragraphStyle: alignLeft
        ]))
        
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(x: 30, y: 30, width: 500, height: 700), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        CTFrameDraw(frame, context)
        
        context.endPage()
        context.closePDF()
        
        return pdfData as Data
    }
}
